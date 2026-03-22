import AVFoundation
import Foundation

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}

enum MediaAudioExtractorError: LocalizedError {
    case sourceNotPlayable
    case exportSessionUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotPlayable:
            return "The selected media item is not playable for local transcription."
        case .exportSessionUnavailable:
            return "Unable to prepare audio extraction for this media item."
        case let .exportFailed(message):
            return message
        }
    }
}

struct ExtractedAudioAsset: Sendable {
    var localURL: URL
    var cleanupAfterUse: Bool
}

actor MediaAudioExtractor {
    func extractAudio(from sourceURL: URL) async throws -> ExtractedAudioAsset {
        if sourceURL.isFileURL, Self.isDirectAudioFile(sourceURL) {
            return ExtractedAudioAsset(localURL: sourceURL, cleanupAfterUse: false)
        }

        let asset = AVURLAsset(url: sourceURL)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw MediaAudioExtractorError.sourceNotPlayable
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaAudioExtractorError.exportSessionUnavailable
        }

        let outputURL = try AppPaths.transcriptionDirectory()
            .appendingPathComponent("\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false

        let exportSessionBox = ExportSessionBox(session: exportSession)
        try await withCheckedThrowingContinuation { continuation in
            exportSessionBox.session.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: MediaAudioExtractorError.exportFailed(
                        exportSessionBox.session.error?.localizedDescription ?? "Audio extraction failed."
                    ))
                case .cancelled:
                    continuation.resume(throwing: MediaAudioExtractorError.exportFailed("Audio extraction was cancelled."))
                default:
                    continuation.resume(throwing: MediaAudioExtractorError.exportFailed("Audio extraction did not complete."))
                }
            }
        }

        return ExtractedAudioAsset(localURL: outputURL, cleanupAfterUse: true)
    }

    private static func isDirectAudioFile(_ url: URL) -> Bool {
        let audioExtensions = ["m4a", "mp3", "wav", "flac", "aac", "caf", "aiff"]
        return audioExtensions.contains(url.pathExtension.lowercased())
    }
}
