import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AVPlayerCoordinator {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let player = AVPlayer()

    var status: Status = .idle
    var currentTimeText = "00:00"
    var durationText = "--:--"
    var isPlaying = false
    /// Live channel captions from `SFSpeechRecognizer` (when tap is active).
    var liveCaptionText: String = ""

    private let liveSpeech = LiveSpeechTranscriber()
    private var pendingResumePositionMs: Int64 = 0
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?

    var currentPositionMs: Int64 {
        guard player.currentTime().isNumeric else { return 0 }
        return Int64(max(player.currentTime().seconds, 0) * 1_000)
    }

    var currentDurationMs: Int64 {
        guard let duration = player.currentItem?.duration, duration.isNumeric, duration.seconds.isFinite else {
            return 0
        }
        return Int64(max(duration.seconds, 0) * 1_000)
    }

    func load(_ presentation: PlaybackPresentation, resumePositionMs: Int64 = 0) {
        liveSpeech.stop()
        liveCaptionText = ""
        resetObservers()

        status = .loading
        currentTimeText = "00:00"
        durationText = presentation.kind == .live ? "LIVE" : "--:--"
        pendingResumePositionMs = presentation.kind == .live ? 0 : resumePositionMs

        let item = playerItem(for: presentation)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch observedItem.status {
                case .unknown:
                    self.status = .loading
                case .readyToPlay:
                    self.status = .ready
                    if self.pendingResumePositionMs > 0 {
                        let seekTime = CMTime(
                            seconds: Double(self.pendingResumePositionMs) / 1_000,
                            preferredTimescale: 600
                        )
                        self.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            self.player.play()
                        }
                        self.pendingResumePositionMs = 0
                    } else {
                        self.player.play()
                    }
                    self.updateTimeStrings()
                case .failed:
                    self.status = .failed(observedItem.error?.localizedDescription ?? "Playback failed to start.")
                @unknown default:
                    self.status = .failed("Playback failed to start.")
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = observedPlayer.timeControlStatus == .playing
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTimeStrings()
            }
        }

        player.replaceCurrentItem(with: item)

        if presentation.kind == .live {
            Task { [weak self] in
                guard let self else { return }
                await self.liveSpeech.attachIfPossible(to: item) { [weak self] text in
                    self?.liveCaptionText = text
                }
            }
        }
    }

    func stop() {
        liveSpeech.stop()
        liveCaptionText = ""
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetObservers()
        pendingResumePositionMs = 0
        status = .idle
        currentTimeText = "00:00"
        durationText = "--:--"
        isPlaying = false
    }
    private func updateTimeStrings() {
        let currentTime = player.currentTime()
        currentTimeText = Self.format(time: currentTime)

        if let duration = player.currentItem?.duration, duration.isNumeric, duration.seconds.isFinite {
            durationText = Self.format(time: duration)
        } else if player.currentItem == nil {
            durationText = "--:--"
        }
    }

    private var vttResourceLoader: VTTResourceLoader?

    private func playerItem(for presentation: PlaybackPresentation) -> AVPlayerItem {
        let streamURL = presentation.streamURL
        let isHLS = streamURL.absoluteString.contains(".m3u8") || streamURL.pathExtension.lowercased() == "m3u8"
        let vttURL: URL?
        if let relPath = presentation.transcriptPath {
            vttURL = try? AppPaths.resolvedURL(for: relPath)
        } else {
            vttURL = nil
        }

        if isHLS, let vtt = vttURL, FileManager.default.fileExists(atPath: vtt.path),
           let customURL = VTTResourceLoader.customURL(realStreamURL: streamURL, contentId: presentation.id) {
            let loader = VTTResourceLoader(realBaseURL: streamURL, localVTTURL: vtt)
            vttResourceLoader = loader
            let asset = AVURLAsset(url: customURL)
            asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
            return AVPlayerItem(asset: asset)
        }
        vttResourceLoader = nil
        return AVPlayerItem(url: streamURL)
    }

    private func resetObservers() {
        itemObservation = nil
        timeControlObservation = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private static func format(time: CMTime) -> String {
        guard time.isNumeric, time.seconds.isFinite, time.seconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(time.seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
