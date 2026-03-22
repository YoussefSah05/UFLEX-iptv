import XCTest
import GRDB
@testable import YOUFLEXiOS

final class AppDatabaseTests: XCTestCase {
    func testInsertAndFetchMovie() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var movie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "Inception",
                rawTitle: "Inception (2010)",
                streamUrl: "https://cdn.example.com/inception.mp4",
                streamUrlHash: "hash-inception",
                year: 2010,
                runtime: 148,
                posterPath: "/tmp/poster.jpg",
                backdropPath: "/tmp/backdrop.jpg",
                synopsis: "A dream-heist thriller.",
                genres: "[\"Sci-Fi\"]",
                director: "Christopher Nolan",
                cast: "[\"Leonardo DiCaprio\"]",
                imdbId: "tt1375666",
                tmdbId: 27205,
                enrichmentStatus: "ready",
                transcriptStatus: "none",
                addedAt: now
            )
            try movie.insert(db)
        }

        let movie = try database.dbQueue.read { db in
            try MovieRecord.fetchOne(db, key: "movie-1")
        }

        XCTAssertEqual(movie?.title, "Inception")
        XCTAssertEqual(movie?.year, 2010)
        XCTAssertEqual(movie?.runtime, 148)
        XCTAssertEqual(movie?.imdbId, "tt1375666")
    }

    func testDuplicateStreamUrlHashIsRejected() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var firstMovie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "First",
                rawTitle: "First",
                streamUrl: "https://cdn.example.com/first.mp4",
                streamUrlHash: "duplicate-hash",
                year: nil,
                runtime: nil,
                posterPath: nil,
                backdropPath: nil,
                synopsis: nil,
                genres: nil,
                director: nil,
                cast: nil,
                imdbId: nil,
                tmdbId: nil,
                enrichmentStatus: "pending",
                transcriptStatus: "none",
                addedAt: now
            )
            try firstMovie.insert(db)

            XCTAssertThrowsError(
                try {
                    var secondMovie = MovieRecord(
                    id: "movie-2",
                    providerId: "provider-1",
                    title: "Second",
                    rawTitle: "Second",
                    streamUrl: "https://cdn.example.com/second.mp4",
                    streamUrlHash: "duplicate-hash",
                    year: nil,
                    runtime: nil,
                    posterPath: nil,
                    backdropPath: nil,
                    synopsis: nil,
                    genres: nil,
                    director: nil,
                    cast: nil,
                    imdbId: nil,
                    tmdbId: nil,
                    enrichmentStatus: "pending",
                    transcriptStatus: "none",
                    addedAt: now
                    )
                    try secondMovie.insert(db)
                }()
            )
        }
    }

    func testMovieFTSReturnsInsertedMovie() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var movie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "Inception",
                rawTitle: "Inception (2010)",
                streamUrl: "https://cdn.example.com/inception.mp4",
                streamUrlHash: "hash-inception",
                year: 2010,
                runtime: 148,
                posterPath: nil,
                backdropPath: nil,
                synopsis: "Dreams inside dreams.",
                genres: nil,
                director: "Christopher Nolan",
                cast: nil,
                imdbId: nil,
                tmdbId: nil,
                enrichmentStatus: "ready",
                transcriptStatus: "none",
                addedAt: now
            )
            try movie.insert(db)
        }

        let results = try database.searchCatalog("inception")
        XCTAssertTrue(results.contains(where: { $0.id == "movie-1" && $0.kind == "movie" }))
    }

    func testFetchEpisodesReturnsSeasonAndEpisodeOrder() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var series = SeriesRecord(
                id: "series-1",
                providerId: "provider-1",
                title: "Breakpoint",
                totalSeasons: 2,
                totalEpisodes: 3,
                genres: "Drama",
                status: nil,
                posterPath: nil,
                backdropPath: nil,
                synopsis: nil,
                tmdbId: nil,
                tvdbId: nil,
                enrichmentStatus: "pending"
            )
            try series.insert(db)

            var seasonOne = SeasonRecord(
                id: "season-1",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeCount: 2,
                year: nil,
                posterPath: nil
            )
            try seasonOne.insert(db)

            var seasonTwo = SeasonRecord(
                id: "season-2",
                seriesId: "series-1",
                seasonNumber: 2,
                episodeCount: 1,
                year: nil,
                posterPath: nil
            )
            try seasonTwo.insert(db)

            var episodeThree = EpisodeRecord(
                id: "episode-3",
                seriesId: "series-1",
                seasonId: "season-2",
                seasonNumber: 2,
                episodeNumber: 1,
                title: "Fault Line",
                streamUrl: "https://cdn.example.com/breakpoint-s02e01.m3u8",
                streamUrlHash: "ep-3",
                synopsis: nil,
                runtime: 43,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
            try episodeThree.insert(db)

            var episodeTwo = EpisodeRecord(
                id: "episode-2",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 2,
                title: "Second Strike",
                streamUrl: "https://cdn.example.com/breakpoint-s01e02.m3u8",
                streamUrlHash: "ep-2",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
            try episodeTwo.insert(db)

            var episodeOne = EpisodeRecord(
                id: "episode-1",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Pilot",
                streamUrl: "https://cdn.example.com/breakpoint-s01e01.m3u8",
                streamUrlHash: "ep-1",
                synopsis: nil,
                runtime: 41,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
            try episodeOne.insert(db)
        }

        let episodes = try database.fetchEpisodes(seriesId: "series-1")
        XCTAssertEqual(episodes.map(\.id), ["episode-1", "episode-2", "episode-3"])
    }

    func testContinueWatchingReturnsMostRecentMovieAndEpisodeProgress() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var movie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "Neon City",
                rawTitle: "Neon City",
                streamUrl: "https://cdn.example.com/neon-city.mp4",
                streamUrlHash: "movie-hash",
                year: 2024,
                runtime: 110,
                posterPath: nil,
                backdropPath: nil,
                synopsis: "A city thriller.",
                genres: nil,
                director: nil,
                cast: nil,
                imdbId: nil,
                tmdbId: nil,
                enrichmentStatus: "pending",
                transcriptStatus: "none",
                addedAt: now
            )
            try movie.insert(db)

            var series = SeriesRecord(
                id: "series-1",
                providerId: "provider-1",
                title: "Breakpoint",
                totalSeasons: 1,
                totalEpisodes: 1,
                genres: nil,
                status: nil,
                posterPath: nil,
                backdropPath: nil,
                synopsis: nil,
                tmdbId: nil,
                tvdbId: nil,
                enrichmentStatus: "pending"
            )
            try series.insert(db)

            var season = SeasonRecord(
                id: "season-1",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeCount: 1,
                year: nil,
                posterPath: nil
            )
            try season.insert(db)

            var episode = EpisodeRecord(
                id: "episode-1",
                seriesId: "series-1",
                seasonId: "season-1",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Pilot",
                streamUrl: "https://cdn.example.com/breakpoint-s01e01.mp4",
                streamUrlHash: "episode-hash",
                synopsis: nil,
                runtime: 44,
                airDate: nil,
                thumbnailPath: nil,
                transcriptStatus: "none"
            )
            try episode.insert(db)
        }

        try database.saveMovieProgress(
            MovieProgressRecord(
                movieId: "movie-1",
                positionMs: 600_000,
                durationMs: 6_000_000,
                watchedPercent: 0.1,
                completed: false,
                lastWatchedAt: now
            )
        )

        try database.saveEpisodeProgress(
            EpisodeProgressRecord(
                episodeId: "episode-1",
                seriesId: "series-1",
                seasonNumber: 1,
                episodeNumber: 1,
                positionMs: 1_200_000,
                durationMs: 2_400_000,
                watchedPercent: 0.5,
                completed: false,
                lastWatchedAt: now.addingTimeInterval(120)
            )
        )

        let items = try database.fetchContinueWatching(limit: 5)

        XCTAssertEqual(items.map(\.kind), ["episode", "movie"])
        XCTAssertEqual(items.first?.subtitle, "Breakpoint · S01 E01")
        XCTAssertEqual(items.last?.title, "Neon City")
    }

    func testApplyMovieEnrichmentUpdatesStoredMetadata() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var movie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "Neon City",
                rawTitle: "Neon City",
                streamUrl: "https://cdn.example.com/neon-city.mp4",
                streamUrlHash: "movie-hash",
                year: nil,
                runtime: nil,
                posterPath: nil,
                backdropPath: nil,
                synopsis: nil,
                genres: nil,
                director: nil,
                cast: nil,
                imdbId: nil,
                tmdbId: nil,
                enrichmentStatus: "pending",
                transcriptStatus: "none",
                addedAt: now
            )
            try movie.insert(db)
        }

        try database.applyMovieEnrichment(
            MovieEnrichmentUpdate(
                movieId: "movie-1",
                tmdbId: 101,
                posterPath: "https://image.tmdb.org/t/p/w342/poster.jpg",
                backdropPath: "https://image.tmdb.org/t/p/w780/backdrop.jpg",
                synopsis: "Updated overview.",
                genres: "Drama, Sci-Fi",
                runtime: 119,
                year: 2025,
                enrichmentStatus: "ready"
            )
        )

        let movie = try database.fetchMovie(id: "movie-1")
        XCTAssertEqual(movie?.tmdbId, 101)
        XCTAssertEqual(movie?.posterPath, "https://image.tmdb.org/t/p/w342/poster.jpg")
        XCTAssertEqual(movie?.synopsis, "Updated overview.")
        XCTAssertEqual(movie?.runtime, 119)
        XCTAssertEqual(movie?.year, 2025)
        XCTAssertEqual(movie?.enrichmentStatus, "ready")
    }

    func testReplaceTranscriptSegmentsStoresAndFetchesTranscriptRows() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()

        try database.dbQueue.write { db in
            var provider = ProviderRecord(
                id: "provider-1",
                name: "Primary",
                type: "m3u_url",
                m3uUrl: "https://example.com/feed.m3u8",
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var movie = MovieRecord(
                id: "movie-1",
                providerId: "provider-1",
                title: "Neon City",
                rawTitle: "Neon City",
                streamUrl: "https://cdn.example.com/neon-city.mp4",
                streamUrlHash: "neon-city",
                year: 2024,
                runtime: 110,
                posterPath: nil,
                backdropPath: nil,
                synopsis: nil,
                genres: nil,
                director: nil,
                cast: nil,
                imdbId: nil,
                tmdbId: nil,
                enrichmentStatus: "pending",
                transcriptStatus: "none",
                addedAt: now
            )
            try movie.insert(db)
        }

        try database.replaceTranscriptSegments(
            contentId: "movie-1",
            contentType: TranscriptContentType.movie.rawValue,
            language: "en",
            segments: [
                GeneratedTranscriptSegment(
                    startMs: 0,
                    endMs: 2_000,
                    text: "Hello world",
                    confidence: 0.9,
                    words: [
                        TranscriptWordPayload(word: "Hello", startMs: 0, endMs: 900, probability: 0.95)
                    ]
                )
            ]
        )
        try database.updateTranscriptStatus(contentId: "movie-1", contentType: TranscriptContentType.movie.rawValue, status: "ready")

        let segments = try database.fetchTranscriptSegments(contentId: "movie-1", contentType: TranscriptContentType.movie.rawValue)
        let movie = try database.fetchMovie(id: "movie-1")

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "Hello world")
        XCTAssertEqual(movie?.transcriptStatus, "ready")
        XCTAssertEqual(segments.first?.decodedWords.first?.word, "Hello")
    }

    func testUpsertAndFetchCompletedDownload() throws {
        let database = try AppDatabase.makeInMemory()
        let now = Date()
        let download = DownloadRecord(
            id: "download-movie-1",
            contentId: "movie-1",
            contentType: "movie",
            title: "Neon City",
            sourceUrl: "https://cdn.example.com/neon-city.mp4",
            localRelativePath: "Downloads/download-movie-1.mp4",
            status: "completed",
            bytesDownloaded: 100,
            expectedBytes: 100,
            failureMessage: nil,
            createdAt: now,
            updatedAt: now
        )

        try database.upsertDownload(download)

        let completed = try database.fetchCompletedDownload(contentId: "movie-1", contentType: "movie")
        XCTAssertEqual(completed?.id, "download-movie-1")
        XCTAssertEqual(completed?.status, "completed")
    }
}
