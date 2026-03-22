import Foundation
import GRDB

struct ProviderRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "provider"

    var id: String
    var name: String
    var type: String
    var m3uUrl: String?
    var xtreamServer: String?
    var lastRefreshedAt: Date?
    var refreshIntervalHours: Int
}

struct ChannelRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "channel"

    var id: String
    var providerId: String
    var title: String
    var rawTitle: String
    var streamUrl: String
    var streamUrlHash: String
    var category: String?
    var tvgId: String?
    var tvgName: String?
    var logoUrl: String?
    var epgChannelId: String?
    var country: String?
    var isHD: Bool
    var sortOrder: Int
}

struct MovieRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "movie"

    var id: String
    var providerId: String
    var title: String
    var rawTitle: String
    var streamUrl: String
    var streamUrlHash: String
    var year: Int?
    var runtime: Int?
    var posterPath: String?
    var backdropPath: String?
    var synopsis: String?
    var genres: String?
    var director: String?
    var cast: String?
    var imdbId: String?
    var tmdbId: Int?
    var enrichmentStatus: String
    var transcriptStatus: String
    var transcriptPath: String?
    var addedAt: Date
}

struct SeriesRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "series"

    var id: String
    var providerId: String
    var title: String
    var totalSeasons: Int
    var totalEpisodes: Int
    var genres: String?
    var status: String?
    var posterPath: String?
    var backdropPath: String?
    var synopsis: String?
    var tmdbId: Int?
    var tvdbId: Int?
    var enrichmentStatus: String
}

struct SeasonRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "season"

    var id: String
    var seriesId: String
    var seasonNumber: Int
    var episodeCount: Int
    var year: Int?
    var posterPath: String?
}

struct EpisodeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "episode"

    var id: String
    var seriesId: String
    var seasonId: String
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String
    var streamUrl: String
    var streamUrlHash: String
    var synopsis: String?
    var runtime: Int?
    var airDate: Date?
    var thumbnailPath: String?
    var transcriptStatus: String
    var transcriptPath: String?
}

struct MovieProgressRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "movieProgress"

    var movieId: String
    var positionMs: Int64
    var durationMs: Int64
    var watchedPercent: Double
    var completed: Bool
    var lastWatchedAt: Date
}

struct EpisodeProgressRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "episodeProgress"

    var episodeId: String
    var seriesId: String
    var seasonNumber: Int
    var episodeNumber: Int
    var positionMs: Int64
    var durationMs: Int64
    var watchedPercent: Double
    var completed: Bool
    var lastWatchedAt: Date
}

struct EPGProgramRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "epgProgram"

    var id: String
    var channelId: String
    var title: String
    var synopsis: String?
    var startTime: Date
    var endTime: Date
    var category: String?
}

struct TranscriptSegmentRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "transcriptSegment"

    var id: String
    var contentId: String
    var contentType: String
    var language: String
    var startMs: Int64
    var endMs: Int64
    var text: String
    var words: String?
    var confidence: Double?
}

struct ImportJobRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "importJob"

    var id: String
    var providerId: String
    var phase: String
    var cursorType: String?
    var cursorValue: String?
    var processedItems: Int
    var totalItems: Int
    var channels: Int
    var movies: Int
    var series: Int
    var episodes: Int
    var createdAt: Date
    var updatedAt: Date

    // Pipeline progress (migration v5)
    var stage: String?
    var linesRead: Int?
    var parsedCount: Int?
    var classifiedLive: Int?
    var classifiedMovie: Int?
    var classifiedSeries: Int?
    var classifiedUncertain: Int?
    var dedupSkipped: Int?
    var enrichedCount: Int?
    var failedCount: Int?
    var estimatedSecondsRemaining: Int?
}

struct DownloadRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "downloadItem"

    var id: String
    var contentId: String
    var contentType: String
    var title: String
    var sourceUrl: String
    var localRelativePath: String?
    var status: String
    var bytesDownloaded: Int64
    var expectedBytes: Int64
    var failureMessage: String?
    var createdAt: Date
    var updatedAt: Date
}

struct LibrarySummary {
    var providerCount: Int
    var channelCount: Int
    var movieCount: Int
    var seriesCount: Int
    var episodeCount: Int

    static let empty = LibrarySummary(
        providerCount: 0,
        channelCount: 0,
        movieCount: 0,
        seriesCount: 0,
        episodeCount: 0
    )
}

struct ProviderImportSummary: Sendable {
    var providerId: String
    var providerName: String
    var channels: Int
    var movies: Int
    var series: Int
    var episodes: Int
}

struct SearchResultItem: Identifiable, FetchableRecord, Decodable {
    var id: String
    var title: String
    var kind: String
}

struct ContinueWatchingItem: FetchableRecord, Decodable, Identifiable {
    var contentId: String
    var kind: String
    var title: String
    var subtitle: String?
    var synopsis: String?
    var streamUrl: String
    var progressPercent: Double
    var positionMs: Int64
    var durationMs: Int64
    var lastWatchedAt: Date

    var id: String {
        "\(kind)-\(contentId)"
    }
}

struct MovieEnrichmentUpdate: Sendable {
    var movieId: String
    var tmdbId: Int
    var posterPath: String?
    var backdropPath: String?
    var synopsis: String?
    var genres: String?
    var runtime: Int?
    var year: Int?
    var enrichmentStatus: String
}

struct SeriesEnrichmentUpdate: Sendable {
    var seriesId: String
    var tmdbId: Int
    var posterPath: String?
    var backdropPath: String?
    var synopsis: String?
    var genres: String?
    var status: String?
    var enrichmentStatus: String
}
