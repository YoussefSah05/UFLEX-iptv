import Foundation

enum LibraryTranscriptionError: LocalizedError {
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "Live channels are not part of the VOD transcription path."
        }
    }
}

final class LibraryTranscriptionCoordinator: @unchecked Sendable {
    private let database: AppDatabase
    private let transcriber = WhisperKitTranscriber()

    init(database: AppDatabase) {
        self.database = database
    }

    func transcribe(presentation: PlaybackPresentation, preferredModel: String) async throws -> Int {
        guard let contentType = presentation.transcriptContentType else {
            throw LibraryTranscriptionError.unsupportedContent
        }

        try database.updateTranscriptStatus(contentId: presentation.id, contentType: contentType.rawValue, status: "in_progress")

        do {
            let transcript = try await transcriber.transcribe(mediaURL: presentation.streamURL, preferredModel: preferredModel)
            try database.replaceTranscriptSegments(
                contentId: presentation.id,
                contentType: contentType.rawValue,
                language: transcript.language,
                segments: transcript.segments
            )

            let vttContent = VTTBuilder.build(segments: transcript.segments)
            let vttFilename = "\(contentType.rawValue)-\(presentation.id).vtt"
            let vttDir = try AppPaths.transcriptionDirectory()
            let vttURL = vttDir.appendingPathComponent(vttFilename)
            try vttContent.write(to: vttURL, atomically: true, encoding: .utf8)
            let relativePath = try AppPaths.relativePath(for: vttURL)
            try database.updateTranscriptPath(contentId: presentation.id, contentType: contentType.rawValue, relativePath: relativePath)

            try database.updateTranscriptStatus(contentId: presentation.id, contentType: contentType.rawValue, status: "ready")
            NotificationCenter.default.post(name: .youflexLibraryDidChange, object: nil)
            return transcript.segments.count
        } catch {
            try? database.updateTranscriptStatus(contentId: presentation.id, contentType: contentType.rawValue, status: "failed")
            NotificationCenter.default.post(name: .youflexLibraryDidChange, object: nil)
            throw error
        }
    }

    func transcribePendingLibrary(preferredModel: String, limit: Int = 2) async -> LibraryTranscriptionSummary {
        var summary = LibraryTranscriptionSummary()

        do {
            for movie in try database.fetchMoviesNeedingTranscription(limit: limit) {
                do {
                    _ = try await transcribe(
                        presentation: PlaybackPresentation(movie: movie),
                        preferredModel: preferredModel
                    )
                    summary.moviesTranscribed += 1
                } catch {
                    summary.failures += 1
                }
            }

            for episode in try database.fetchEpisodesNeedingTranscription(limit: limit) {
                do {
                    let seriesTitle = try database.fetchSeries(id: episode.seriesId)?.title
                    _ = try await transcribe(
                        presentation: PlaybackPresentation(episode: episode, seriesTitle: seriesTitle),
                        preferredModel: preferredModel
                    )
                    summary.episodesTranscribed += 1
                } catch {
                    summary.failures += 1
                }
            }
        } catch {
            summary.failures += 1
        }

        return summary
    }
}
