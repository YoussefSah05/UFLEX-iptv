import Foundation

struct SeriesPlaybackTarget {
    enum Mode: Equatable {
        case start
        case resume
        case next

        var actionTitle: String {
            switch self {
            case .start:
                return "Start Series"
            case .resume:
                return "Resume Episode"
            case .next:
                return "Watch Next Episode"
            }
        }
    }

    var episode: EpisodeRecord
    var progress: EpisodeProgressRecord?
    var mode: Mode
}

enum NextEpisodeResolver {
    static func resolve(
        episodes: [EpisodeRecord],
        progressByEpisodeID: [String: EpisodeProgressRecord]
    ) -> SeriesPlaybackTarget? {
        guard !episodes.isEmpty else { return nil }

        let resumable = episodes
            .compactMap { episode -> SeriesPlaybackTarget? in
                guard let progress = progressByEpisodeID[episode.id] else { return nil }
                let resumePosition = ProgressTracker.resumePositionMs(
                    positionMs: progress.positionMs,
                    durationMs: progress.durationMs,
                    completed: progress.completed
                )
                guard resumePosition > 0 else { return nil }
                return SeriesPlaybackTarget(episode: episode, progress: progress, mode: .resume)
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.progress?.lastWatchedAt, let rhsDate = rhs.progress?.lastWatchedAt else {
                    return false
                }
                return lhsDate > rhsDate
            }
            .first

        if let resumable {
            return resumable
        }

        if let next = episodes.first(where: { !(progressByEpisodeID[$0.id]?.completed ?? false) }) {
            return SeriesPlaybackTarget(
                episode: next,
                progress: progressByEpisodeID[next.id],
                mode: .next
            )
        }

        return SeriesPlaybackTarget(
            episode: episodes[0],
            progress: progressByEpisodeID[episodes[0].id],
            mode: .start
        )
    }
}
