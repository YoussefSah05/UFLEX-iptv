import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    @MainActor
    static let shared: AppDatabase = {
        do {
            return try AppDatabase(path: try AppPaths.databaseURL().path)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    let dbQueue: DatabaseQueue
    let databasePath: String

    init(path: String) throws {
        self.databasePath = path
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    init(namedInMemory _: String = UUID().uuidString) throws {
        self.databasePath = ":memory:"
        self.dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(namedInMemory: UUID().uuidString)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "provider") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("m3uUrl", .text)
                t.column("xtreamServer", .text)
                t.column("lastRefreshedAt", .datetime)
                t.column("refreshIntervalHours", .integer).notNull().defaults(to: 24)
            }

            try db.create(table: "channel") { t in
                t.primaryKey("id", .text)
                t.column("providerId", .text).notNull().references("provider", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("rawTitle", .text).notNull()
                t.column("streamUrl", .text).notNull()
                t.column("streamUrlHash", .text).notNull().unique()
                t.column("category", .text)
                t.column("tvgId", .text)
                t.column("tvgName", .text)
                t.column("logoUrl", .text)
                t.column("epgChannelId", .text)
                t.column("country", .text)
                t.column("isHD", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "movie") { t in
                t.primaryKey("id", .text)
                t.column("providerId", .text).notNull().references("provider", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("rawTitle", .text).notNull()
                t.column("streamUrl", .text).notNull()
                t.column("streamUrlHash", .text).notNull().unique()
                t.column("year", .integer)
                t.column("runtime", .integer)
                t.column("posterPath", .text)
                t.column("backdropPath", .text)
                t.column("synopsis", .text)
                t.column("genres", .text)
                t.column("director", .text)
                t.column("cast", .text)
                t.column("imdbId", .text)
                t.column("tmdbId", .integer)
                t.column("enrichmentStatus", .text).notNull().defaults(to: "pending")
                t.column("transcriptStatus", .text).notNull().defaults(to: "none")
                t.column("addedAt", .datetime).notNull()
            }

            try db.create(table: "series") { t in
                t.primaryKey("id", .text)
                t.column("providerId", .text).notNull().references("provider", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("totalSeasons", .integer).notNull().defaults(to: 0)
                t.column("totalEpisodes", .integer).notNull().defaults(to: 0)
                t.column("genres", .text)
                t.column("status", .text)
                t.column("posterPath", .text)
                t.column("backdropPath", .text)
                t.column("synopsis", .text)
                t.column("tmdbId", .integer)
                t.column("tvdbId", .integer)
                t.column("enrichmentStatus", .text).notNull().defaults(to: "pending")
            }

            try db.create(table: "season") { t in
                t.primaryKey("id", .text)
                t.column("seriesId", .text).notNull().references("series", onDelete: .cascade)
                t.column("seasonNumber", .integer).notNull()
                t.column("episodeCount", .integer).notNull().defaults(to: 0)
                t.column("year", .integer)
                t.column("posterPath", .text)
            }

            try db.create(table: "episode") { t in
                t.primaryKey("id", .text)
                t.column("seriesId", .text).notNull().references("series", onDelete: .cascade)
                t.column("seasonId", .text).notNull().references("season", onDelete: .cascade)
                t.column("seasonNumber", .integer).notNull()
                t.column("episodeNumber", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("streamUrl", .text).notNull()
                t.column("streamUrlHash", .text).notNull().unique()
                t.column("synopsis", .text)
                t.column("runtime", .integer)
                t.column("airDate", .date)
                t.column("thumbnailPath", .text)
                t.column("transcriptStatus", .text).notNull().defaults(to: "none")
            }

            try db.create(table: "movieProgress") { t in
                t.column("movieId", .text).notNull().references("movie", onDelete: .cascade).primaryKey()
                t.column("positionMs", .integer).notNull().defaults(to: 0)
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("watchedPercent", .double).notNull().defaults(to: 0)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("lastWatchedAt", .datetime).notNull()
            }

            try db.create(table: "episodeProgress") { t in
                t.column("episodeId", .text).notNull().references("episode", onDelete: .cascade).primaryKey()
                t.column("seriesId", .text).notNull()
                t.column("seasonNumber", .integer).notNull()
                t.column("episodeNumber", .integer).notNull()
                t.column("positionMs", .integer).notNull().defaults(to: 0)
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("watchedPercent", .double).notNull().defaults(to: 0)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("lastWatchedAt", .datetime).notNull()
            }

            try db.create(table: "epgProgram") { t in
                t.primaryKey("id", .text)
                t.column("channelId", .text).notNull().references("channel", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("synopsis", .text)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime).notNull()
                t.column("category", .text)
            }

            try db.create(index: "epgProgram_channel_time_idx", on: "epgProgram", columns: ["channelId", "startTime", "endTime"])

            try db.create(table: "transcriptSegment") { t in
                t.primaryKey("id", .text)
                t.column("contentId", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("language", .text).notNull()
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("words", .text)
                t.column("confidence", .double)
            }

            try db.create(table: "importJob") { t in
                t.primaryKey("id", .text)
                t.column("providerId", .text).notNull().references("provider", onDelete: .cascade)
                t.column("phase", .text).notNull()
                t.column("cursorType", .text)
                t.column("cursorValue", .text)
                t.column("processedItems", .integer).notNull().defaults(to: 0)
                t.column("totalItems", .integer).notNull().defaults(to: 0)
                t.column("channels", .integer).notNull().defaults(to: 0)
                t.column("movies", .integer).notNull().defaults(to: 0)
                t.column("series", .integer).notNull().defaults(to: 0)
                t.column("episodes", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try registerFTS(
                db: db,
                table: "movie",
                virtualTable: "movieFTS",
                indexedColumns: ["title", "synopsis", "director"],
                unindexedColumns: ["id"]
            )
            try registerFTS(
                db: db,
                table: "series",
                virtualTable: "seriesFTS",
                indexedColumns: ["title", "synopsis"],
                unindexedColumns: ["id"]
            )
            try registerFTS(
                db: db,
                table: "channel",
                virtualTable: "channelFTS",
                indexedColumns: ["title", "rawTitle", "category", "tvgName"],
                unindexedColumns: ["id"]
            )
            try registerFTS(
                db: db,
                table: "transcriptSegment",
                virtualTable: "transcriptFTS",
                indexedColumns: ["text"],
                unindexedColumns: ["contentId", "contentType"]
            )
        }

        migrator.registerMigration("v2_stream_url_support") { db in
            if try !db.columns(in: "channel").contains(where: { $0.name == "streamUrl" }) {
                try db.alter(table: "channel") { t in
                    t.add(column: "streamUrl", .text).notNull().defaults(to: "")
                }
            }
            if try !db.columns(in: "movie").contains(where: { $0.name == "streamUrl" }) {
                try db.alter(table: "movie") { t in
                    t.add(column: "streamUrl", .text).notNull().defaults(to: "")
                }
            }
            if try !db.columns(in: "episode").contains(where: { $0.name == "streamUrl" }) {
                try db.alter(table: "episode") { t in
                    t.add(column: "streamUrl", .text).notNull().defaults(to: "")
                }
            }
        }

        migrator.registerMigration("v3_downloads_and_transcripts") { db in
            try db.create(table: "downloadItem", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("contentId", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("title", .text).notNull()
                t.column("sourceUrl", .text).notNull()
                t.column("localRelativePath", .text)
                t.column("status", .text).notNull().defaults(to: "queued")
                t.column("bytesDownloaded", .integer).notNull().defaults(to: 0)
                t.column("expectedBytes", .integer).notNull().defaults(to: 0)
                t.column("failureMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "downloadItem_content_idx",
                on: "downloadItem",
                columns: ["contentId", "contentType"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("v4_transcript_path") { db in
            if try !db.columns(in: "movie").contains(where: { $0.name == "transcriptPath" }) {
                try db.alter(table: "movie") { t in
                    t.add(column: "transcriptPath", .text)
                }
            }
            if try !db.columns(in: "episode").contains(where: { $0.name == "transcriptPath" }) {
                try db.alter(table: "episode") { t in
                    t.add(column: "transcriptPath", .text)
                }
            }
        }

        migrator.registerMigration("v5_import_pipeline_progress") { db in
            let existingColumns = try Set(db.columns(in: "importJob").map(\.name))
            if !existingColumns.contains("stage") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "stage", .text)
                }
            }
            if !existingColumns.contains("linesRead") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "linesRead", .integer)
                }
            }
            if !existingColumns.contains("parsedCount") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "parsedCount", .integer)
                }
            }
            if !existingColumns.contains("classifiedLive") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "classifiedLive", .integer)
                }
            }
            if !existingColumns.contains("classifiedMovie") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "classifiedMovie", .integer)
                }
            }
            if !existingColumns.contains("classifiedSeries") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "classifiedSeries", .integer)
                }
            }
            if !existingColumns.contains("classifiedUncertain") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "classifiedUncertain", .integer)
                }
            }
            if !existingColumns.contains("dedupSkipped") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "dedupSkipped", .integer)
                }
            }
            if !existingColumns.contains("enrichedCount") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "enrichedCount", .integer)
                }
            }
            if !existingColumns.contains("failedCount") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "failedCount", .integer)
                }
            }
            if !existingColumns.contains("estimatedSecondsRemaining") {
                try db.alter(table: "importJob") { t in
                    t.add(column: "estimatedSecondsRemaining", .integer)
                }
            }
        }

        return migrator
    }

    func fetchLibrarySummary() throws -> LibrarySummary {
        try dbQueue.read { db in
            LibrarySummary(
                providerCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM provider") ?? 0,
                channelCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM channel") ?? 0,
                movieCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM movie") ?? 0,
                seriesCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM series") ?? 0,
                episodeCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode") ?? 0
            )
        }
    }

    func fetchChannels(limit: Int = 25) throws -> [ChannelRecord] {
        try dbQueue.read { db in
            try ChannelRecord
                .order(Column("sortOrder"), Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchProviders() throws -> [ProviderRecord] {
        try dbQueue.read { db in
            try ProviderRecord
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    func fetchMovies(limit: Int = 25) throws -> [MovieRecord] {
        try dbQueue.read { db in
            try MovieRecord
                .order(Column("addedAt").desc, Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSeries(limit: Int = 25) throws -> [SeriesRecord] {
        try dbQueue.read { db in
            try SeriesRecord
                .order(Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchMoviesNeedingEnrichment(limit: Int = 20) throws -> [MovieRecord] {
        try dbQueue.read { db in
            try MovieRecord
                .filter(Column("enrichmentStatus") != "ready")
                .order(Column("addedAt").desc, Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSeriesNeedingEnrichment(limit: Int = 20) throws -> [SeriesRecord] {
        try dbQueue.read { db in
            try SeriesRecord
                .filter(Column("enrichmentStatus") != "ready")
                .order(Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchChannel(id: String) throws -> ChannelRecord? {
        try dbQueue.read { db in
            try ChannelRecord.fetchOne(db, key: id)
        }
    }

    func fetchEPGPrograms(channelId: String, from: Date? = nil, to: Date? = nil, limit: Int = 50) throws -> [EPGProgramRecord] {
        try dbQueue.read { db in
            var request = EPGProgramRecord
                .filter(Column("channelId") == channelId)

            if let from {
                request = request.filter(Column("startTime") >= from)
            }
            if let to {
                request = request.filter(Column("endTime") <= to)
            }
            return try request
                .order(Column("startTime"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchMovie(id: String) throws -> MovieRecord? {
        try dbQueue.read { db in
            try MovieRecord.fetchOne(db, key: id)
        }
    }

    func fetchSeries(id: String) throws -> SeriesRecord? {
        try dbQueue.read { db in
            try SeriesRecord.fetchOne(db, key: id)
        }
    }

    func fetchEpisode(id: String) throws -> EpisodeRecord? {
        try dbQueue.read { db in
            try EpisodeRecord.fetchOne(db, key: id)
        }
    }

    func fetchEpisodes(seriesId: String, limit: Int? = nil) throws -> [EpisodeRecord] {
        try dbQueue.read { db in
            var request = EpisodeRecord
                .filter(Column("seriesId") == seriesId)
                .order(Column("seasonNumber"), Column("episodeNumber"), Column("title"))

            if let limit {
                request = request.limit(limit)
            }

            return try request.fetchAll(db)
        }
    }

    func fetchMovieProgress() throws -> [MovieProgressRecord] {
        try dbQueue.read { db in
            try MovieProgressRecord.fetchAll(db)
        }
    }

    func fetchEpisodeProgress() throws -> [EpisodeProgressRecord] {
        try dbQueue.read { db in
            try EpisodeProgressRecord.fetchAll(db)
        }
    }

    func saveMovieProgress(_ progress: MovieProgressRecord) throws {
        try dbQueue.write { db in
            var progress = progress
            try progress.save(db)
        }
    }

    func saveEpisodeProgress(_ progress: EpisodeProgressRecord) throws {
        try dbQueue.write { db in
            var progress = progress
            try progress.save(db)
        }
    }

    func fetchTranscriptSegments(contentId: String, contentType: String) throws -> [TranscriptSegmentRecord] {
        try dbQueue.read { db in
            try TranscriptSegmentRecord
                .filter(Column("contentId") == contentId && Column("contentType") == contentType)
                .order(Column("startMs"), Column("endMs"))
                .fetchAll(db)
        }
    }

    func replaceTranscriptSegments(
        contentId: String,
        contentType: String,
        language: String,
        segments: [GeneratedTranscriptSegment]
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM transcriptSegment WHERE contentId = ? AND contentType = ?",
                arguments: [contentId, contentType]
            )

            let encoder = JSONEncoder()
            for (index, segment) in segments.enumerated() {
                let wordsJSON: String?
                if segment.words.isEmpty {
                    wordsJSON = nil
                } else {
                    wordsJSON = String(data: try encoder.encode(segment.words), encoding: .utf8)
                }
                var record = TranscriptSegmentRecord(
                    id: "transcript-\(contentType)-\(contentId)-\(index)",
                    contentId: contentId,
                    contentType: contentType,
                    language: language,
                    startMs: segment.startMs,
                    endMs: segment.endMs,
                    text: segment.text,
                    words: wordsJSON,
                    confidence: segment.confidence
                )
                try record.insert(db)
            }
        }
    }

    func updateTranscriptStatus(contentId: String, contentType: String, status: String) throws {
        try dbQueue.write { db in
            switch contentType {
            case TranscriptContentType.movie.rawValue:
                try db.execute(
                    sql: "UPDATE movie SET transcriptStatus = ? WHERE id = ?",
                    arguments: [status, contentId]
                )
            case TranscriptContentType.episode.rawValue:
                try db.execute(
                    sql: "UPDATE episode SET transcriptStatus = ? WHERE id = ?",
                    arguments: [status, contentId]
                )
            default:
                break
            }
        }
    }

    func updateTranscriptPath(contentId: String, contentType: String, relativePath: String?) throws {
        try dbQueue.write { db in
            switch contentType {
            case TranscriptContentType.movie.rawValue:
                try db.execute(
                    sql: "UPDATE movie SET transcriptPath = ? WHERE id = ?",
                    arguments: [relativePath, contentId]
                )
            case TranscriptContentType.episode.rawValue:
                try db.execute(
                    sql: "UPDATE episode SET transcriptPath = ? WHERE id = ?",
                    arguments: [relativePath, contentId]
                )
            default:
                break
            }
        }
    }

    func fetchMoviesNeedingTranscription(limit: Int = 2) throws -> [MovieRecord] {
        try dbQueue.read { db in
            try MovieRecord
                .filter(Column("transcriptStatus") != "ready")
                .order(Column("addedAt").desc, Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchEpisodesNeedingTranscription(limit: Int = 2) throws -> [EpisodeRecord] {
        try dbQueue.read { db in
            try EpisodeRecord
                .filter(Column("transcriptStatus") != "ready")
                .order(Column("seasonNumber"), Column("episodeNumber"), Column("title"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchDownloads(limit: Int = 50) throws -> [DownloadRecord] {
        try dbQueue.read { db in
            try DownloadRecord
                .order(Column("updatedAt").desc, Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchDownload(id: String) throws -> DownloadRecord? {
        try dbQueue.read { db in
            try DownloadRecord.fetchOne(db, key: id)
        }
    }

    func fetchCompletedDownload(contentId: String, contentType: String) throws -> DownloadRecord? {
        try dbQueue.read { db in
            try DownloadRecord
                .filter(Column("contentId") == contentId && Column("contentType") == contentType && Column("status") == "completed")
                .fetchOne(db)
        }
    }

    func upsertDownload(_ record: DownloadRecord) throws {
        try dbQueue.write { db in
            var record = record
            try record.save(db)
        }
    }

    func updateDownloadStatus(
        id: String,
        status: String,
        bytesDownloaded: Int64,
        expectedBytes: Int64,
        failureMessage: String?
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE downloadItem
                SET status = ?, bytesDownloaded = ?, expectedBytes = ?, failureMessage = ?, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [status, bytesDownloaded, expectedBytes, failureMessage, Date(), id]
            )
        }
    }

    func updateDownloadCompletion(id: String, localRelativePath: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE downloadItem
                SET status = 'completed', localRelativePath = ?, failureMessage = NULL, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [localRelativePath, Date(), id]
            )
        }
    }

    func applyMovieEnrichment(_ update: MovieEnrichmentUpdate) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE movie
                SET
                    tmdbId = ?,
                    posterPath = coalesce(?, posterPath),
                    backdropPath = coalesce(?, backdropPath),
                    synopsis = coalesce(?, synopsis),
                    genres = coalesce(?, genres),
                    runtime = coalesce(?, runtime),
                    year = coalesce(?, year),
                    enrichmentStatus = ?
                WHERE id = ?
                """,
                arguments: [
                    update.tmdbId,
                    update.posterPath,
                    update.backdropPath,
                    update.synopsis,
                    update.genres,
                    update.runtime,
                    update.year,
                    update.enrichmentStatus,
                    update.movieId
                ]
            )
        }
    }

    func applySeriesEnrichment(_ update: SeriesEnrichmentUpdate) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE series
                SET
                    tmdbId = ?,
                    posterPath = coalesce(?, posterPath),
                    backdropPath = coalesce(?, backdropPath),
                    synopsis = coalesce(?, synopsis),
                    genres = coalesce(?, genres),
                    status = coalesce(?, status),
                    enrichmentStatus = ?
                WHERE id = ?
                """,
                arguments: [
                    update.tmdbId,
                    update.posterPath,
                    update.backdropPath,
                    update.synopsis,
                    update.genres,
                    update.status,
                    update.enrichmentStatus,
                    update.seriesId
                ]
            )
        }
    }

    func markMovieEnrichmentUnmatched(movieId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE movie SET enrichmentStatus = 'unmatched' WHERE id = ?",
                arguments: [movieId]
            )
        }
    }

    func markSeriesEnrichmentUnmatched(seriesId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE series SET enrichmentStatus = 'unmatched' WHERE id = ?",
                arguments: [seriesId]
            )
        }
    }

    func fetchContinueWatching(limit: Int = 12) throws -> [ContinueWatchingItem] {
        try dbQueue.read { db in
            try ContinueWatchingItem.fetchAll(
                db,
                sql: """
                SELECT *
                FROM (
                    SELECT
                        movie.id AS contentId,
                        'movie' AS kind,
                        movie.title AS title,
                        CASE
                            WHEN movie.year IS NOT NULL THEN CAST(movie.year AS TEXT)
                            ELSE movie.genres
                        END AS subtitle,
                        movie.synopsis AS synopsis,
                        movie.streamUrl AS streamUrl,
                        movieProgress.watchedPercent AS progressPercent,
                        movieProgress.positionMs AS positionMs,
                        movieProgress.durationMs AS durationMs,
                        movieProgress.lastWatchedAt AS lastWatchedAt
                    FROM movieProgress
                    JOIN movie ON movie.id = movieProgress.movieId
                    WHERE movieProgress.completed = 0
                      AND movieProgress.positionMs > 0

                    UNION ALL

                    SELECT
                        episode.id AS contentId,
                        'episode' AS kind,
                        episode.title AS title,
                        printf('%s · S%02d E%02d', series.title, episode.seasonNumber, episode.episodeNumber) AS subtitle,
                        episode.synopsis AS synopsis,
                        episode.streamUrl AS streamUrl,
                        episodeProgress.watchedPercent AS progressPercent,
                        episodeProgress.positionMs AS positionMs,
                        episodeProgress.durationMs AS durationMs,
                        episodeProgress.lastWatchedAt AS lastWatchedAt
                    FROM episodeProgress
                    JOIN episode ON episode.id = episodeProgress.episodeId
                    JOIN series ON series.id = episode.seriesId
                    WHERE episodeProgress.completed = 0
                      AND episodeProgress.positionMs > 0
                )
                ORDER BY lastWatchedAt DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    func searchCatalog(_ query: String, limit: Int = 12) throws -> [SearchResultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }

        return try dbQueue.read { db in
            let match = buildFTSMatchQuery(trimmed)
            let channels = try SearchResultItem.fetchAll(
                db,
                sql: """
                SELECT channel.id, channel.title, 'channel' AS kind
                FROM channelFTS
                JOIN channel ON channelFTS.rowid = channel.rowid
                WHERE channelFTS MATCH ?
                LIMIT ?
                """,
                arguments: [match, limit]
            )
            let movies = try SearchResultItem.fetchAll(
                db,
                sql: """
                SELECT movie.id, movie.title, 'movie' AS kind
                FROM movieFTS
                JOIN movie ON movieFTS.rowid = movie.rowid
                WHERE movieFTS MATCH ?
                LIMIT ?
                """,
                arguments: [match, limit]
            )
            let series = try SearchResultItem.fetchAll(
                db,
                sql: """
                SELECT series.id, series.title, 'series' AS kind
                FROM seriesFTS
                JOIN series ON seriesFTS.rowid = series.rowid
                WHERE seriesFTS MATCH ?
                LIMIT ?
                """,
                arguments: [match, limit]
            )

            return channels + movies + series
        }
    }

    func fetchImportJob(id: String) throws -> ImportJobRecord? {
        try dbQueue.read { db in
            try ImportJobRecord.fetchOne(db, key: id)
        }
    }

    func fetchActiveImportJob(providerId: String) throws -> ImportJobRecord? {
        try dbQueue.read { db in
            try ImportJobRecord
                .filter(Column("providerId") == providerId)
                .filter(Column("phase") != "completed")
                .filter(Column("phase") != "failed")
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    func upsertImportJobProgress(
        jobId: String,
        phase: String,
        progress: ImportPipelineProgress,
        cursorType: String?,
        cursorValue: String?,
        channels: Int,
        movies: Int,
        series: Int,
        episodes: Int
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE importJob SET
                    phase = ?,
                    stage = ?,
                    linesRead = ?,
                    parsedCount = ?,
                    classifiedLive = ?,
                    classifiedMovie = ?,
                    classifiedSeries = ?,
                    classifiedUncertain = ?,
                    dedupSkipped = ?,
                    enrichedCount = ?,
                    failedCount = ?,
                    estimatedSecondsRemaining = ?,
                    cursorType = ?,
                    cursorValue = ?,
                    processedItems = ?,
                    channels = ?,
                    movies = ?,
                    series = ?,
                    episodes = ?,
                    updatedAt = ?
                WHERE id = ?
                """,
                arguments: [
                    phase,
                    progress.stage.rawValue,
                    progress.linesRead,
                    progress.parsedCount,
                    progress.classifiedLive,
                    progress.classifiedMovie,
                    progress.classifiedSeries,
                    progress.classifiedUncertain,
                    progress.dedupSkipped,
                    progress.enrichedCount,
                    progress.failedCount,
                    progress.estimatedSecondsRemaining,
                    cursorType,
                    cursorValue,
                    progress.totalClassified,
                    channels,
                    movies,
                    series,
                    episodes,
                    Date(),
                    jobId
                ]
            )
        }
    }

    func insertChannelsBatch(_ records: [ChannelRecord]) throws -> Int {
        try insertBatch(records, batchSize: 500) { db, record in
            var r = record
            try r.save(db)
        }
    }

    func insertMoviesBatch(_ records: [MovieRecord]) throws -> Int {
        try insertBatch(records, batchSize: 500) { db, record in
            var r = record
            try r.save(db)
        }
    }

    func insertEpisodesBatch(_ records: [EpisodeRecord]) throws -> Int {
        try insertBatch(records, batchSize: 500) { db, record in
            var r = record
            try r.save(db)
        }
    }

    func insertSeasonsBatch(_ records: [SeasonRecord]) throws -> Int {
        try insertBatch(records, batchSize: 500) { db, record in
            var r = record
            try r.save(db)
        }
    }

    func insertSeriesBatch(_ records: [SeriesRecord]) throws -> Int {
        try insertBatch(records, batchSize: 500) { db, record in
            var r = record
            try r.save(db)
        }
    }

    private func insertBatch<T>(
        _ records: [T],
        batchSize: Int,
        insert: (Database, T) throws -> Void
    ) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            var offset = 0
            while offset < records.count {
                let end = min(offset + batchSize, records.count)
                try db.inTransaction {
                    for i in offset..<end {
                        try insert(db, records[i])
                        inserted += 1
                    }
                    return .commit
                }
                offset = end
            }
            return inserted
        }
    }

    func channelExists(streamUrlHash: String) throws -> Bool {
        try dbQueue.read { db in
            try ChannelRecord
                .filter(Column("streamUrlHash") == streamUrlHash)
                .fetchCount(db) > 0
        }
    }

    func movieExists(streamUrlHash: String) throws -> Bool {
        try dbQueue.read { db in
            try MovieRecord
                .filter(Column("streamUrlHash") == streamUrlHash)
                .fetchCount(db) > 0
        }
    }

    func episodeExists(streamUrlHash: String) throws -> Bool {
        try dbQueue.read { db in
            try EpisodeRecord
                .filter(Column("streamUrlHash") == streamUrlHash)
                .fetchCount(db) > 0
        }
    }

    func applyEPG(result: XMLTVResult) throws -> Int {
        var inserted = 0
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM epgProgram")

            let channels = try ChannelRecord.fetchAll(db)
            var xmltvToChannelId: [String: String] = [:]
            for ch in channels {
                if let epgId = ch.epgChannelId {
                    xmltvToChannelId[epgId] = ch.id
                }
                if let tvgId = ch.tvgId {
                    xmltvToChannelId[tvgId] = ch.id
                }
            }

            for prog in result.programmes {
                guard let channelId = xmltvToChannelId[prog.channelId] else { continue }
                let id = "epg-\(channelId)-\(prog.start.timeIntervalSince1970)"
                var record = EPGProgramRecord(
                    id: id,
                    channelId: channelId,
                    title: prog.title,
                    synopsis: prog.description,
                    startTime: prog.start,
                    endTime: prog.stop,
                    category: prog.category
                )
                try record.save(db)
                inserted += 1
            }
        }
        return inserted
    }
}

private func buildFTSMatchQuery(_ query: String) -> String {
    query
        .split(whereSeparator: \.isWhitespace)
        .map { token in
            let sanitized = token.replacingOccurrences(of: "\"", with: "")
            return "\(sanitized)*"
        }
        .joined(separator: " ")
}

private func registerFTS(
    db: Database,
    table: String,
    virtualTable: String,
    indexedColumns: [String],
    unindexedColumns: [String]
) throws {
    let allVirtualColumns = indexedColumns + unindexedColumns.map { "\($0) UNINDEXED" }
    let quotedColumns = indexedColumns + unindexedColumns

    try db.execute(sql: """
    CREATE VIRTUAL TABLE \(virtualTable) USING fts5(
      \(allVirtualColumns.joined(separator: ", ")),
      content='\(table)',
      content_rowid='rowid'
    )
    """)

    let valueExpressions = quotedColumns.map { "coalesce(new.\($0), '')" }.joined(separator: ", ")
    let oldValueExpressions = quotedColumns.map { "coalesce(old.\($0), '')" }.joined(separator: ", ")

    try db.execute(sql: """
    CREATE TRIGGER \(virtualTable)_ai AFTER INSERT ON \(table) BEGIN
      INSERT INTO \(virtualTable)(rowid, \(quotedColumns.joined(separator: ", ")))
      VALUES (new.rowid, \(valueExpressions));
    END;
    """)

    try db.execute(sql: """
    CREATE TRIGGER \(virtualTable)_ad AFTER DELETE ON \(table) BEGIN
      INSERT INTO \(virtualTable)(\(virtualTable), rowid, \(quotedColumns.joined(separator: ", ")))
      VALUES('delete', old.rowid, \(oldValueExpressions));
    END;
    """)

    try db.execute(sql: """
    CREATE TRIGGER \(virtualTable)_au AFTER UPDATE ON \(table) BEGIN
      INSERT INTO \(virtualTable)(\(virtualTable), rowid, \(quotedColumns.joined(separator: ", ")))
      VALUES('delete', old.rowid, \(oldValueExpressions));
      INSERT INTO \(virtualTable)(rowid, \(quotedColumns.joined(separator: ", ")))
      VALUES (new.rowid, \(valueExpressions));
    END;
    """)
}
