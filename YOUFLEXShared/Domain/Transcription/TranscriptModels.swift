import Foundation

enum TranscriptContentType: String, Sendable {
    case movie
    case episode
}

struct TranscriptWordPayload: Codable, Hashable, Sendable {
    var word: String
    var startMs: Int64
    var endMs: Int64
    var probability: Double
}

struct GeneratedTranscriptSegment: Sendable {
    var startMs: Int64
    var endMs: Int64
    var text: String
    var confidence: Double?
    var words: [TranscriptWordPayload]
}

struct GeneratedTranscript: Sendable {
    var language: String
    var text: String
    var segments: [GeneratedTranscriptSegment]
}

struct LibraryTranscriptionSummary: Sendable {
    var moviesTranscribed: Int = 0
    var episodesTranscribed: Int = 0
    var failures: Int = 0
}

extension PlaybackPresentation {
    var transcriptContentType: TranscriptContentType? {
        switch kind {
        case .live:
            return nil
        case .movie:
            return .movie
        case .episode:
            return .episode
        }
    }
}

extension TranscriptSegmentRecord {
    var decodedWords: [TranscriptWordPayload] {
        guard let words else {
            return []
        }
        return (try? JSONDecoder().decode([TranscriptWordPayload].self, from: Data(words.utf8))) ?? []
    }
}
