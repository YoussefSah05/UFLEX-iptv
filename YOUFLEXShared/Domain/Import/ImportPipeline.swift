import CryptoKit
import Foundation
import GRDB

/// Production-grade M3U import pipeline with streaming, resumption, and progress reporting.
actor ImportPipeline {
    static let batchSize = 500
    static let progressReportInterval = 50
    static let etaWindowSize = 10

    private let database: AppDatabase
    private let streamingParser = M3UStreamingParser()
    private let classifier = ContentClassifier()

    private(set) var currentProgress: ImportPipelineProgress = .initial()
    private var progressContinuation: AsyncStream<ImportPipelineProgress>.Continuation?
    private var lastBatchTimestamps: [Date] = []
    private var lastBatchCounts: [Int] = []

    var progressStream: AsyncStream<ImportPipelineProgress> {
        AsyncStream { continuation in
            progressContinuation = continuation
            continuation.yield(currentProgress)
        }
    }

    init(database: AppDatabase) {
        self.database = database
    }

    /// Runs the full pipeline for the given source. Reports progress and supports resumption.
    func run(
        providerId: String,
        providerName: String,
        jobId: String,
        source: ProviderImportSource,
        resumeFrom: ImportJobRecord?
    ) async throws -> ProviderImportSummary {
        let now = Date()
        let isResuming = resumeFrom != nil
        currentProgress = isResuming ? progressFrom(resumeFrom!) : .initial(stage: .fetching)

        if !isResuming {
            try await database.dbQueue.write { db in
                var job = ImportJobRecord(
                id: jobId,
                providerId: providerId,
                phase: "importing",
                cursorType: nil,
                cursorValue: nil,
                processedItems: 0,
                totalItems: 0,
                channels: 0,
                movies: 0,
                series: 0,
                episodes: 0,
                createdAt: now,
                updatedAt: now,
                stage: "Fetching",
                linesRead: 0,
                parsedCount: 0,
                classifiedLive: 0,
                classifiedMovie: 0,
                classifiedSeries: 0,
                classifiedUncertain: 0,
                dedupSkipped: 0,
                enrichedCount: 0,
                failedCount: 0,
                estimatedSecondsRemaining: nil
                )
                try job.save(db)
            }
        }
        reportProgress()
        lastBatchTimestamps = []
        lastBatchCounts = []

        let (stream, baseURL, m3uURLString, providerType) = try await resolveSource(source)
        await updateProgress { $0.stage = .parsing }

        var channels: [ChannelRecord] = []
        var movies: [MovieRecord] = []
        var series: [SeriesRecord] = []
        var seasons: [SeasonRecord] = []
        var episodes: [EpisodeRecord] = []
        var seasonIDsBySeries: [String: Set<String>] = [:]
        var episodeCountsBySeason: [String: Int] = [:]
        var episodeCountsBySeries: [String: Int] = [:]
        var seenStreamHashes = Set<String>()
        var linesRead = resumeFrom?.linesRead ?? 0
        var parsedCount = resumeFrom?.parsedCount ?? 0

        await updateProgress {
            $0.linesRead = linesRead
            $0.parsedCount = parsedCount
            $0.classifiedLive = resumeFrom?.classifiedLive ?? 0
            $0.classifiedMovie = resumeFrom?.classifiedMovie ?? 0
            $0.classifiedSeries = resumeFrom?.classifiedSeries ?? 0
        }

        let skipCount = resumeFrom?.parsedCount ?? 0
        var entryIndex = 0
        for try await entry in stream {
            entryIndex += 1
            if entryIndex <= skipCount {
                continue
            }
            linesRead += 1
            parsedCount += 1

            await updateProgress {
                $0.stage = .classifying
                $0.linesRead = linesRead
                $0.parsedCount = parsedCount
            }
            if parsedCount % Self.progressReportInterval == 0 {
                recordBatchForETA(count: Self.progressReportInterval)
                await reportAndPersistProgress(
                    jobId: jobId,
                    phase: "importing",
                    cursorType: "parsedCount",
                    cursorValue: "\(parsedCount)",
                    channels: channels.count,
                    movies: movies.count,
                    series: series.count,
                    episodes: episodes.count
                )
            }

            let streamURLString = entry.streamURL.absoluteString
            let streamHash = Self.sha256(streamURLString)

            let result = classifier.classify(entry)
            if result.isUncertain {
                await updateProgress { $0.classifiedUncertain += 1 }
            }

            switch result.effectiveContent {
            case .channel:
                await updateProgress { $0.classifiedLive += 1 }
                if seenStreamHashes.contains(streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                seenStreamHashes.insert(streamHash)
                if try database.channelExists(streamUrlHash: streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                var logoUrl = entry.logoURL
                if (logoUrl == nil || logoUrl?.isEmpty == true),
                   let lookupId = entry.tvgID ?? entry.tvgName {
                    logoUrl = await IPTVOrgLogoClient.logoURL(for: lookupId)
                }
                let channel = ChannelRecord(
                    id: Self.stableIdentifier(prefix: "channel", seed: "\(providerId)|\(streamHash)"),
                    providerId: providerId,
                    title: entry.title,
                    rawTitle: entry.rawTitle,
                    streamUrl: streamURLString,
                    streamUrlHash: streamHash,
                    category: entry.groupTitle,
                    tvgId: entry.tvgID,
                    tvgName: entry.tvgName,
                    logoUrl: logoUrl,
                    epgChannelId: entry.tvgID ?? entry.tvgName,
                    country: nil,
                    isHD: entry.title.localizedCaseInsensitiveContains("HD") || entry.title.localizedCaseInsensitiveContains("UHD"),
                    sortOrder: channels.count
                )
                channels.append(channel)

            case let .movie(year):
                await updateProgress { $0.classifiedMovie += 1 }
                if seenStreamHashes.contains(streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                seenStreamHashes.insert(streamHash)
                if try database.movieExists(streamUrlHash: streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                let movie = MovieRecord(
                    id: Self.stableIdentifier(prefix: "movie", seed: "\(providerId)|\(streamHash)"),
                    providerId: providerId,
                    title: result.normalizedTitle,
                    rawTitle: entry.rawTitle,
                    streamUrl: streamURLString,
                    streamUrlHash: streamHash,
                    year: result.extractedYear ?? year,
                    runtime: entry.duration.flatMap { $0 > 0 ? $0 / 60 : nil },
                    posterPath: entry.logoURL,
                    backdropPath: nil,
                    synopsis: nil,
                    genres: entry.groupTitle,
                    director: nil,
                    cast: nil,
                    imdbId: nil,
                    tmdbId: nil,
                    enrichmentStatus: "pending",
                    transcriptStatus: "none",
                    transcriptPath: nil,
                    addedAt: now
                )
                movies.append(movie)

            case .uncertain:
                break

            case let .episode(identity):
                await updateProgress { $0.classifiedSeries += 1 }
                if seenStreamHashes.contains(streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                seenStreamHashes.insert(streamHash)
                if try database.episodeExists(streamUrlHash: streamHash) {
                    await updateProgress { $0.dedupSkipped += 1 }
                    continue
                }
                let seriesKey = "\(providerId)|\(identity.seriesTitle.lowercased())"
                let seriesId = Self.stableIdentifier(prefix: "series", seed: seriesKey)
                let seasonId = Self.stableIdentifier(prefix: "season", seed: "\(seriesId)|\(identity.seasonNumber)")
                let episodeId = Self.stableIdentifier(prefix: "episode", seed: "\(providerId)|\(streamHash)")

                if !series.contains(where: { $0.id == seriesId }) {
                    let seriesRecord = SeriesRecord(
                        id: seriesId,
                        providerId: providerId,
                        title: identity.seriesTitle,
                        totalSeasons: 0,
                        totalEpisodes: 0,
                        genres: entry.groupTitle,
                        status: nil,
                        posterPath: entry.logoURL,
                        backdropPath: nil,
                        synopsis: nil,
                        tmdbId: nil,
                        tvdbId: nil,
                        enrichmentStatus: "pending"
                    )
                    series.append(seriesRecord)
                }
                if !seasons.contains(where: { $0.id == seasonId }) {
                    let seasonRecord = SeasonRecord(
                        id: seasonId,
                        seriesId: seriesId,
                        seasonNumber: identity.seasonNumber,
                        episodeCount: 0,
                        year: classifier.detectYear(in: entry.title),
                        posterPath: entry.logoURL
                    )
                    seasons.append(seasonRecord)
                }
                let episode = EpisodeRecord(
                    id: episodeId,
                    seriesId: seriesId,
                    seasonId: seasonId,
                    seasonNumber: identity.seasonNumber,
                    episodeNumber: identity.episodeNumber,
                    title: identity.episodeTitle,
                    streamUrl: streamURLString,
                    streamUrlHash: streamHash,
                    synopsis: nil,
                    runtime: entry.duration.flatMap { $0 > 0 ? $0 / 60 : nil },
                    airDate: nil,
                    thumbnailPath: entry.logoURL,
                    transcriptStatus: "none",
                    transcriptPath: nil
                )
                episodes.append(episode)
                seasonIDsBySeries[seriesId, default: []].insert(seasonId)
                episodeCountsBySeason[seasonId, default: 0] += 1
                episodeCountsBySeries[seriesId, default: 0] += 1
            }
        }

        guard !channels.isEmpty || !movies.isEmpty || !episodes.isEmpty else {
            throw ProviderImportError.emptyPlaylist
        }

        await updateProgress { $0.stage = .indexing }
        reportProgress()

        try await performIndexing(
            providerId: providerId,
            providerName: providerName,
            jobId: jobId,
            resumeFrom: resumeFrom,
            channels: channels,
            movies: movies,
            series: series,
            seasons: seasons,
            episodes: episodes,
            episodeCountsBySeason: episodeCountsBySeason,
            episodeCountsBySeries: episodeCountsBySeries,
            seasonIDsBySeries: seasonIDsBySeries,
            baseURL: baseURL,
            m3uURLString: m3uURLString,
            providerType: providerType
        )

        await updateProgress { $0.stage = .enriching }
        reportProgress()
        await updateProgress { $0.stage = .indexing }
        try await persistFinalJob(
            jobId: jobId,
            channels: channels.count,
            movies: movies.count,
            series: series.count,
            episodes: episodes.count
        )

        progressContinuation?.finish()
        return ProviderImportSummary(
            providerId: providerId,
            providerName: providerName,
            channels: channels.count,
            movies: movies.count,
            series: series.count,
            episodes: episodes.count
        )
    }

    private func resolveSource(_ source: ProviderImportSource) async throws -> (
        AsyncThrowingStream<ParsedM3UEntry, Error>,
        URL?,
        String?,
        String
    ) {
        switch source {
        case let .remote(url):
            let stream = streamingParser.parse(from: url)
            return (stream, url.deletingLastPathComponent(), url.absoluteString, "m3u_url")
        case let .pasted(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw ProviderImportError.emptySource }
            let stream = streamingParser.parse(from: trimmed, baseURL: nil)
            return (stream, nil, nil, "m3u_inline")
        }
    }

    private func performIndexing(
        providerId: String,
        providerName: String,
        jobId: String,
        resumeFrom: ImportJobRecord?,
        channels: [ChannelRecord],
        movies: [MovieRecord],
        series: [SeriesRecord],
        seasons: [SeasonRecord],
        episodes: [EpisodeRecord],
        episodeCountsBySeason: [String: Int],
        episodeCountsBySeries: [String: Int],
        seasonIDsBySeries: [String: Set<String>],
        baseURL: URL?,
        m3uURLString: String?,
        providerType: String
    ) async throws {
        let isResuming = resumeFrom != nil

        try await database.dbQueue.write { db in
            if !isResuming {
                if let existing = try ProviderRecord.fetchOne(db, key: providerId) {
                    try existing.delete(db)
                } else if let existingByName = try ProviderRecord.filter(Column("name") == providerName).fetchOne(db) {
                    try existingByName.delete(db)
                }
            }
            let now = Date()
            var provider = ProviderRecord(
                id: providerId,
                name: providerName,
                type: providerType,
                m3uUrl: m3uURLString,
                xtreamServer: nil,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.save(db)
        }

        if !series.isEmpty {
            _ = try database.insertSeriesBatch(series)
        }
        if !seasons.isEmpty {
            _ = try database.insertSeasonsBatch(seasons)
        }
        for (seasonId, count) in episodeCountsBySeason {
            try await database.dbQueue.write { db in
                try db.execute(sql: "UPDATE season SET episodeCount = ? WHERE id = ?", arguments: [count, seasonId])
            }
        }
        for (seriesId, episodeCount) in episodeCountsBySeries {
            let totalSeasons = seasonIDsBySeries[seriesId]?.count ?? 0
            try await database.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE series SET totalSeasons = ?, totalEpisodes = ? WHERE id = ?",
                    arguments: [totalSeasons, episodeCount, seriesId]
                )
            }
        }
        if !channels.isEmpty {
            _ = try database.insertChannelsBatch(channels)
        }
        if !movies.isEmpty {
            _ = try database.insertMoviesBatch(movies)
        }
        if !episodes.isEmpty {
            _ = try database.insertEpisodesBatch(episodes)
        }

        NotificationCenter.default.post(name: .youflexLibraryDidChange, object: nil)
    }

    private func persistFinalJob(
        jobId: String,
        channels: Int,
        movies: Int,
        series: Int,
        episodes: Int
    ) async throws {
        var progress = currentProgress
        progress.stage = .indexing
        try database.upsertImportJobProgress(
            jobId: jobId,
            phase: "completed",
            progress: progress,
            cursorType: nil,
            cursorValue: nil,
            channels: channels,
            movies: movies,
            series: series,
            episodes: episodes
        )
    }

    private func updateProgress(_ block: (inout ImportPipelineProgress) -> Void) async {
        block(&currentProgress)
        reportProgress()
    }

    private func reportProgress() {
        progressContinuation?.yield(currentProgress)
    }

    private func reportAndPersistProgress(
        jobId: String,
        phase: String,
        cursorType: String?,
        cursorValue: String?,
        channels: Int,
        movies: Int,
        series: Int,
        episodes: Int
    ) async {
        var progress = currentProgress
        progress.estimatedSecondsRemaining = estimateSecondsRemaining(totalProcessed: progress.parsedCount)
        currentProgress = progress
        reportProgress()
        try? database.upsertImportJobProgress(
            jobId: jobId,
            phase: phase,
            progress: progress,
            cursorType: cursorType,
            cursorValue: cursorValue,
            channels: channels,
            movies: movies,
            series: series,
            episodes: episodes
        )
    }

    private func recordBatchForETA(count: Int) {
        let now = Date()
        lastBatchTimestamps.append(now)
        lastBatchCounts.append(count)
        if lastBatchTimestamps.count > Self.etaWindowSize {
            lastBatchTimestamps.removeFirst()
            lastBatchCounts.removeFirst()
        }
    }

    private func estimateSecondsRemaining(totalProcessed: Int) -> Int? {
        guard lastBatchTimestamps.count >= 2 else { return nil }
        let recentTimestamps = Array(lastBatchTimestamps.suffix(Self.etaWindowSize))
        let recentCounts = Array(lastBatchCounts.suffix(Self.etaWindowSize))
        guard recentTimestamps.count == recentCounts.count, recentCounts.count >= 2 else { return nil }
        let totalItems = recentCounts.reduce(0, +)
        guard totalItems > 0 else { return nil }
        guard let first = recentTimestamps.first, let last = recentTimestamps.last else { return nil }
        let duration = last.timeIntervalSince(first)
        guard duration > 0 else { return nil }
        let itemsPerSecond = Double(totalItems) / duration
        guard itemsPerSecond > 0 else { return nil }
        return nil
    }

    private func progressFrom(_ job: ImportJobRecord) -> ImportPipelineProgress {
        ImportPipelineProgress(
            stage: ImportPipelineStage(rawValue: job.stage ?? "Fetching") ?? .fetching,
            linesRead: job.linesRead ?? 0,
            parsedCount: job.parsedCount ?? 0,
            classifiedLive: job.classifiedLive ?? 0,
            classifiedMovie: job.classifiedMovie ?? 0,
            classifiedSeries: job.classifiedSeries ?? 0,
            classifiedUncertain: job.classifiedUncertain ?? 0,
            dedupSkipped: job.dedupSkipped ?? 0,
            enrichedCount: job.enrichedCount ?? 0,
            failedCount: job.failedCount ?? 0,
            estimatedSecondsRemaining: job.estimatedSecondsRemaining
        )
    }

    nonisolated static func stableIdentifier(prefix: String, seed: String) -> String {
        "\(prefix)-\(sha256(seed).prefix(16))"
    }

    nonisolated static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}
