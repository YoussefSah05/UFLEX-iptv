import CryptoKit
import Foundation
import GRDB

/// Imports catalog from Xtream Codes API into the database.
/// Credentials are read from Keychain by the caller; never stored in DB.
@MainActor
final class XtreamImportCoordinator {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func importProvider(
        name: String,
        serverURL: URL,
        username: String,
        password: String
    ) async throws -> ProviderImportSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw XtreamImportError.emptyName
        }

        let client = XtreamClient(baseURL: serverURL, username: username, password: password)

        let live = try await client.fetchLiveStreams()
        let vod = try await client.fetchVODStreams()
        let seriesList = try await client.fetchSeries()

        var seriesInfoMap: [Int: XtreamSeriesInfo] = [:]
        for xs in seriesList {
            let id = xs.effectiveSeriesId
            if let info = try? await client.fetchSeriesInfo(seriesId: id) {
                seriesInfoMap[id] = info
            }
        }

        let infoMap = seriesInfoMap
        return try await database.dbQueue.write { db in
            let providerId = Self.stableIdentifier(prefix: "provider", seed: "xtream-\(trimmedName.lowercased())-\(serverURL.absoluteString)")
            try ProviderRecord.filter(Column("id") == providerId).deleteAll(db)
            try ProviderRecord.filter(Column("name") == trimmedName).deleteAll(db)

            let now = Date()
            var provider = ProviderRecord(
                id: providerId,
                name: trimmedName,
                type: "xtream",
                m3uUrl: nil,
                xtreamServer: serverURL.absoluteString,
                lastRefreshedAt: now,
                refreshIntervalHours: 24
            )
            try provider.insert(db)

            var summary = ProviderImportSummary(
                providerId: providerId,
                providerName: trimmedName,
                channels: 0,
                movies: 0,
                series: 0,
                episodes: 0
            )

            for stream in live {
                let streamId = stream.effectiveStreamId
                let streamUrl = client.liveStreamURL(streamId: streamId).absoluteString
                let hash = Self.sha256(streamUrl)
                let id = Self.stableIdentifier(prefix: "channel", seed: "\(providerId)-\(hash)")

                var channel = ChannelRecord(
                    id: id,
                    providerId: providerId,
                    title: stream.title,
                    rawTitle: stream.title,
                    streamUrl: streamUrl,
                    streamUrlHash: hash,
                    category: stream.category_id,
                    tvgId: stream.epg_channel_id,
                    tvgName: stream.title,
                    logoUrl: stream.stream_icon,
                    epgChannelId: stream.epg_channel_id,
                    country: nil,
                    isHD: false,
                    sortOrder: stream.effectiveStreamId
                )
                try? channel.insert(db)
                summary.channels += 1
            }

            for stream in vod {
                let streamId = stream.effectiveStreamId
                let container = stream.container_extension ?? "mp4"
                let streamUrl = client.vodStreamURL(streamId: streamId, container: container).absoluteString
                let hash = Self.sha256(streamUrl)
                let id = Self.stableIdentifier(prefix: "movie", seed: "\(providerId)-\(hash)")

                var movie = MovieRecord(
                    id: id,
                    providerId: providerId,
                    title: stream.displayTitle,
                    rawTitle: stream.displayTitle,
                    streamUrl: streamUrl,
                    streamUrlHash: hash,
                    year: stream.year.flatMap(Int.init),
                    runtime: nil,
                    posterPath: stream.stream_icon,
                    backdropPath: nil,
                    synopsis: nil,
                    genres: nil,
                    director: nil,
                    cast: nil,
                    imdbId: nil,
                    tmdbId: nil,
                    enrichmentStatus: "pending",
                    transcriptStatus: "none",
                    transcriptPath: nil,
                    addedAt: now
                )
                try? movie.insert(db)
                summary.movies += 1
            }

            for xs in seriesList {
                let seriesId = xs.effectiveSeriesId
                let info = infoMap[seriesId]
                let episodesBySeason = info?.episodes ?? [:]

                let id = Self.stableIdentifier(prefix: "series", seed: "\(providerId)-series-\(seriesId)")
                var seriesRecord = SeriesRecord(
                    id: id,
                    providerId: providerId,
                    title: xs.title,
                    totalSeasons: 0,
                    totalEpisodes: 0,
                    genres: xs.genre,
                    status: nil,
                    posterPath: xs.cover ?? info?.info?.cover,
                    backdropPath: nil,
                    synopsis: xs.plot ?? info?.info?.plot,
                    tmdbId: nil,
                    tvdbId: nil,
                    enrichmentStatus: "pending"
                )

                var totalEpisodes = 0
                for (seasonNumStr, episodes) in episodesBySeason {
                    let seasonNum = Int(seasonNumStr) ?? 0
                    let seasonId = Self.stableIdentifier(prefix: "season", seed: "\(id)-\(seasonNum)")

                    if try SeriesRecord.fetchOne(db, key: id) == nil {
                        try? seriesRecord.insert(db)
                    }

                    var season = SeasonRecord(
                        id: seasonId,
                        seriesId: id,
                        seasonNumber: seasonNum,
                        episodeCount: episodes.count,
                        year: nil,
                        posterPath: nil
                    )
                    try? season.insert(db)

                    for ep in episodes {
                        let epNum = ep.episode_num ?? 0
                        let streamIdStr = ep.id ?? ""
                        let streamId = Int(streamIdStr) ?? 0
                        let container = ep.container_extension ?? "mp4"
                        let streamUrl = client.episodeStreamURL(streamId: streamId, container: container).absoluteString
                        let hash = Self.sha256(streamUrl)
                        let episodeId = Self.stableIdentifier(prefix: "episode", seed: "\(id)-\(seasonNum)-\(epNum)-\(hash)")

                        var episode = EpisodeRecord(
                            id: episodeId,
                            seriesId: id,
                            seasonId: seasonId,
                            seasonNumber: seasonNum,
                            episodeNumber: epNum,
                            title: ep.title ?? "Episode \(epNum)",
                            streamUrl: streamUrl,
                            streamUrlHash: hash,
                            synopsis: ep.info?.plot,
                            runtime: ep.info?.duration.flatMap(Int.init),
                            airDate: nil,
                            thumbnailPath: ep.info?.movie_image,
                            transcriptStatus: "none",
                            transcriptPath: nil
                        )
                        try? episode.insert(db)
                        totalEpisodes += 1
                    }
                }

                seriesRecord.totalSeasons = episodesBySeason.count
                seriesRecord.totalEpisodes = totalEpisodes
                try? seriesRecord.update(db)
                summary.series += 1
                summary.episodes += totalEpisodes
            }

            return summary
        }
    }
}

private extension XtreamImportCoordinator {
    nonisolated static func stableIdentifier(prefix: String, seed: String) -> String {
        let hash = sha256(seed)
        return "\(prefix)-\(hash.prefix(16))"
    }

    nonisolated static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum XtreamImportError: LocalizedError {
    case emptyName
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Provider name cannot be empty."
        case .invalidURL:
            return "Invalid Xtream server URL."
        }
    }
}
