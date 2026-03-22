import XCTest
@testable import YOUFLEXiOS

final class NextEpisodeResolverTests: XCTestCase {
    func testResolverPrefersMostRecentlyResumedEpisode() {
        let now = Date()
        let episodes = [
            EpisodeRecord(
                id: "episode-1",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Pilot",
                streamUrl: "https://cdn.example.com/ep1.mp4",
                streamUrlHash: "ep1",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            ),
            EpisodeRecord(
                id: "episode-2",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 2,
                title: "Second Strike",
                streamUrl: "https://cdn.example.com/ep2.mp4",
                streamUrlHash: "ep2",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
        ]

        let progress = [
            "episode-1": EpisodeProgressRecord(
                episodeId: "episode-1",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeNumber: 1,
                positionMs: 300_000,
                durationMs: 2_400_000,
                watchedPercent: 0.125,
                completed: false,
                lastWatchedAt: now
            ),
            "episode-2": EpisodeProgressRecord(
                episodeId: "episode-2",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeNumber: 2,
                positionMs: 900_000,
                durationMs: 2_400_000,
                watchedPercent: 0.375,
                completed: false,
                lastWatchedAt: now.addingTimeInterval(120)
            )
        ]

        let target = NextEpisodeResolver.resolve(episodes: episodes, progressByEpisodeID: progress)

        XCTAssertEqual(target?.episode.id, "episode-2")
        XCTAssertEqual(target?.mode, .resume)
    }

    func testResolverFallsBackToFirstUnwatchedEpisode() {
        let episodes = [
            EpisodeRecord(
                id: "episode-1",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Pilot",
                streamUrl: "https://cdn.example.com/ep1.mp4",
                streamUrlHash: "ep1",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            ),
            EpisodeRecord(
                id: "episode-2",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 2,
                title: "Second Strike",
                streamUrl: "https://cdn.example.com/ep2.mp4",
                streamUrlHash: "ep2",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
        ]

        let progress = [
            "episode-1": EpisodeProgressRecord(
                episodeId: "episode-1",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeNumber: 1,
                positionMs: 2_400_000,
                durationMs: 2_400_000,
                watchedPercent: 1,
                completed: true,
                lastWatchedAt: Date()
            )
        ]

        let target = NextEpisodeResolver.resolve(episodes: episodes, progressByEpisodeID: progress)

        XCTAssertEqual(target?.episode.id, "episode-2")
        XCTAssertEqual(target?.mode, .next)
    }
}
