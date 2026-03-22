import AVFoundation
import AudioToolbox
import Foundation
import MediaToolbox
import Speech

/// Attaches an `MTAudioProcessingTap` to live playback and streams PCM into `SFSpeechRecognizer`
/// for on-device captions. Works for progressive and many file-based streams; HLS may not invoke
/// the tap on all configurations.
@MainActor
final class LiveSpeechTranscriber {
    private weak var playerItem: AVPlayerItem?

    /// - Parameter onCaption: Invoked on the main actor with partial or final caption text.
    func attachIfPossible(to item: AVPlayerItem, onCaption: @escaping @MainActor (String) -> Void) async {
        stop()

        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { return }

        let tracks = try? await item.asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks?.first else { return }

        let ctx = LiveSpeechTapContext(recognizer: recognizer) { text in
            Task { @MainActor in
                onCaption(text)
            }
        }

        let retained = Unmanaged.passRetained(ctx).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retained,
            init: Self.tapInit,
            finalize: Self.tapFinalize,
            prepare: Self.tapPrepare,
            unprepare: Self.tapUnprepare,
            process: Self.tapProcess
        )

        var tap: MTAudioProcessingTap?
        let err = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard err == noErr, let tap else {
            Unmanaged<LiveSpeechTapContext>.fromOpaque(retained).release()
            return
        }

        let params = AVMutableAudioMixInputParameters(track: audioTrack)
        params.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        playerItem = item
    }

    func stop() {
        playerItem?.audioMix = nil
        playerItem = nil
    }

    // MARK: - Tap callbacks (C)

    private static let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    private static let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<LiveSpeechTapContext>.fromOpaque(storage).release()
    }

    private static let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, processingFormat in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<LiveSpeechTapContext>.fromOpaque(storage).takeUnretainedValue()
        ctx.prepare(asbd: processingFormat.pointee, maxFrames: maxFrames)
    }

    private static let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<LiveSpeechTapContext>.fromOpaque(storage).takeUnretainedValue()
        ctx.unprepare()
    }

    private static let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<LiveSpeechTapContext>.fromOpaque(storage).takeUnretainedValue()
        ctx.process(
            tap: tap,
            numberFrames: numberFrames,
            flags: flags,
            bufferListInOut: bufferListInOut,
            numberFramesOut: numberFramesOut,
            flagsOut: flagsOut
        )
    }
}

// MARK: - Tap context (retained by MTAudioProcessingTap)

private final class LiveSpeechTapContext: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let onText: (String) -> Void

    private let speechQueue = DispatchQueue(label: "youflex.live.speech", qos: .userInitiated)
    private let requestLock = NSLock()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var processingASBD = AudioStreamBasicDescription()
    private var tapFormat: AVAudioFormat?

    init(recognizer: SFSpeechRecognizer, onText: @escaping (String) -> Void) {
        self.recognizer = recognizer
        self.onText = onText
    }

    deinit {
        speechQueue.sync {
            requestLock.lock()
            request?.endAudio()
            task?.cancel()
            requestLock.unlock()
        }
    }

    func prepare(asbd: AudioStreamBasicDescription, maxFrames: CMItemCount) {
        processingASBD = asbd
        tapFormat = AVAudioFormat(streamDescription: &processingASBD)

        speechQueue.sync { [weak self] in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.endAudio()
            self.task?.cancel()
            self.requestLock.unlock()

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 13, macOS 10.15, *) {
                if self.recognizer.supportsOnDeviceRecognition {
                    req.requiresOnDeviceRecognition = true
                }
            }
            self.requestLock.lock()
            self.request = req
            self.requestLock.unlock()

            self.task = self.recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    self.onText(text)
                }
                if error != nil {
                    self.onText("")
                }
            }
        }
    }

    func unprepare() {
        speechQueue.sync { [weak self] in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.endAudio()
            self.task?.cancel()
            self.request = nil
            self.task = nil
            self.requestLock.unlock()
        }
    }

    func process(
        tap: MTAudioProcessingTap,
        numberFrames: CMItemCount,
        flags: MTAudioProcessingTapFlags,
        bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
        numberFramesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            flagsOut,
            nil,
            numberFramesOut
        )
        guard status == noErr else {
            numberFramesOut.pointee = 0
            return
        }

        requestLock.lock()
        let speechRequest = request
        requestLock.unlock()

        guard let format = tapFormat,
              let speechRequest,
              numberFramesOut.pointee > 0 else { return }

        let frameCount = AVAudioFrameCount(numberFramesOut.pointee)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        copyBufferList(bufferListInOut, to: buffer, format: format)

        let req = speechRequest
        speechQueue.async {
            req.append(buffer)
        }
    }

    private func copyBufferList(_ bufferList: UnsafeMutablePointer<AudioBufferList>, to buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return }
            if format.isInterleaved, abl.count >= 1 {
                let src = abl[0]
                guard let srcData = src.mData else { return }
                memcpy(channelData[0], srcData, Int(src.mDataByteSize))
            } else {
                let channels = min(Int(format.channelCount), abl.count)
                for ch in 0 ..< channels {
                    let src = abl[ch]
                    guard let srcData = src.mData else { continue }
                    memcpy(channelData[ch], srcData, Int(src.mDataByteSize))
                }
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return }
            if format.isInterleaved, abl.count >= 1 {
                let src = abl[0]
                guard let srcData = src.mData else { return }
                memcpy(channelData[0], srcData, Int(src.mDataByteSize))
            } else {
                let channels = min(Int(format.channelCount), abl.count)
                for ch in 0 ..< channels {
                    let src = abl[ch]
                    guard let srcData = src.mData else { continue }
                    memcpy(channelData[ch], srcData, Int(src.mDataByteSize))
                }
            }
        default:
            break
        }
    }
}
