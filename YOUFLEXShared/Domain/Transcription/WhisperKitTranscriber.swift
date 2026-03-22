import Foundation
import WhisperKit

enum WhisperKitTranscriberError: LocalizedError {
    case noSegments

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "WhisperKit did not produce any timed transcript segments."
        }
    }
}

final class WhisperKitTranscriber {
    private let extractor = MediaAudioExtractor()
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    func transcribe(mediaURL: URL, preferredModel: String) async throws -> GeneratedTranscript {
        let extracted = try await extractor.extractAudio(from: mediaURL)
        defer {
            if extracted.cleanupAfterUse {
                try? FileManager.default.removeItem(at: extracted.localURL)
            }
        }

        let whisperKit = try await preparedWhisperKit(preferredModel: preferredModel)
        let decodeOptions = DecodingOptions(
            verbose: false,
            withoutTimestamps: false,
            wordTimestamps: true
        )
        let results = try await whisperKit.transcribe(audioPath: extracted.localURL.path, decodeOptions: decodeOptions)
        let mergedSegments = results
            .flatMap { $0.segments }
            .filter { !$0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }

        guard !mergedSegments.isEmpty else {
            throw WhisperKitTranscriberError.noSegments
        }

        var segments: [GeneratedTranscriptSegment] = []
        segments.reserveCapacity(mergedSegments.count)

        for segment in mergedSegments {
            let rawWords = segment.words ?? []
            var words: [TranscriptWordPayload] = []
            words.reserveCapacity(rawWords.count)

            for word in rawWords {
                words.append(
                    TranscriptWordPayload(
                        word: word.word,
                        startMs: Int64(word.start * 1_000),
                        endMs: Int64(word.end * 1_000),
                        probability: Double(word.probability)
                    )
                )
            }

            let confidence: Double
            if words.isEmpty {
                confidence = max(0, min(1, exp(Double(segment.avgLogprob))))
            } else {
                confidence = words.reduce(0) { $0 + $1.probability } / Double(words.count)
            }
            let generatedSegment = GeneratedTranscriptSegment(
                startMs: Int64(segment.start * 1_000),
                endMs: Int64(segment.end * 1_000),
                text: segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                confidence: confidence,
                words: words
            )
            segments.append(generatedSegment)
        }

        let fullText = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return GeneratedTranscript(
            language: results.first?.language ?? "und",
            text: fullText,
            segments: segments
        )
    }

    private func preparedWhisperKit(preferredModel: String) async throws -> WhisperKit {
        var normalizedModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedModel.isEmpty {
            normalizedModel = WhisperKitModelInfo.recommendedModelIdForCurrentDevice
        }
        if let whisperKit, loadedModel == normalizedModel {
            return whisperKit
        }

        let config = WhisperKitConfig(
            model: normalizedModel.isEmpty ? nil : normalizedModel,
            downloadBase: try AppPaths.whisperModelsDirectory(),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: true
        )
        let whisperKit = try await WhisperKit(config)
        self.whisperKit = whisperKit
        self.loadedModel = normalizedModel
        return whisperKit
    }
}
