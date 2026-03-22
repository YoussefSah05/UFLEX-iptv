import Foundation

/// Fetches catalog data from Xtream Codes API.
/// Pure domain; no SwiftUI/UIKit.
struct XtreamClient: Sendable {
    let baseURL: URL
    let username: String
    let password: String

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    private func apiURL(action: String, extra: [String: String] = [:]) -> URL {
        let apiBase = baseURL.appendingPathComponent("player_api.php")
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action),
        ] + extra.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    func fetchLiveStreams() async throws -> [XtreamLiveStream] {
        let url = apiURL(action: "get_live_streams")
        let (data, _) = try await URLSession.shared.data(from: url)
        let streams = try JSONDecoder().decode([XtreamLiveStream].self, from: data)
        return streams
    }

    func fetchVODStreams() async throws -> [XtreamVODStream] {
        let url = apiURL(action: "get_vod_streams")
        let (data, _) = try await URLSession.shared.data(from: url)
        let streams = try JSONDecoder().decode([XtreamVODStream].self, from: data)
        return streams
    }

    func fetchSeries() async throws -> [XtreamSeries] {
        let url = apiURL(action: "get_series")
        let (data, _) = try await URLSession.shared.data(from: url)
        let series = try JSONDecoder().decode([XtreamSeries].self, from: data)
        return series
    }

    func fetchSeriesInfo(seriesId: Int) async throws -> XtreamSeriesInfo {
        let url = apiURL(action: "get_series_info", extra: ["series_id": String(seriesId)])
        let (data, _) = try await URLSession.shared.data(from: url)
        let info = try JSONDecoder().decode(XtreamSeriesInfo.self, from: data)
        return info
    }

    func liveStreamURL(streamId: Int, extension ext: String = "ts") -> URL {
        baseURL
            .appendingPathComponent("live")
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamId).\(ext)")
    }

    func vodStreamURL(streamId: Int, container: String) -> URL {
        let ext = container.isEmpty ? "mp4" : container
        return baseURL
            .appendingPathComponent("movie")
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamId).\(ext)")
    }

    func episodeStreamURL(streamId: Int, container: String) -> URL {
        let ext = container.isEmpty ? "mp4" : container
        return baseURL
            .appendingPathComponent("series")
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamId).\(ext)")
    }
}

// MARK: - DTOs (Xtream API response shapes)

struct XtreamLiveStream: Codable, Sendable {
    var num: Int?
    var name: String?
    var stream_type: String?
    var stream_id: Int?
    var stream_icon: String?
    var epg_channel_id: String?
    var added: String?
    var category_id: String?
    var custom_sid: String?
    var tv_archive: Int?
    var direct_source: String?
    var tv_archive_duration: Int?

    var effectiveStreamId: Int { stream_id ?? num ?? 0 }
    var title: String { name ?? "Channel \(effectiveStreamId)" }
}

struct XtreamVODStream: Codable, Sendable {
    var num: Int?
    var name: String?
    var title: String?
    var year: String?
    var stream_type: String?
    var stream_id: Int?
    var stream_icon: String?
    var rating: String?
    var rating_5based: Double?
    var added: String?
    var category_id: String?
    var container_extension: String?
    var custom_sid: String?
    var direct_source: String?

    var effectiveStreamId: Int { stream_id ?? num ?? 0 }
    var displayTitle: String { name ?? title ?? "VOD \(effectiveStreamId)" }
}

struct XtreamSeries: Codable, Sendable {
    var num: Int?
    var name: String?
    var series_id: Int?
    var cover: String?
    var plot: String?
    var cast: String?
    var director: String?
    var genre: String?
    var releaseDate: String?
    var last_modified: String?
    var rating: String?
    var rating_5based: Double?
    var category_id: String?

    var effectiveSeriesId: Int { series_id ?? num ?? 0 }
    var title: String { name ?? "Series \(effectiveSeriesId)" }
}

struct XtreamSeriesInfo: Codable, Sendable {
    var info: XtreamSeriesInfoInner?
    var episodes: [String: [XtreamEpisode]]?

    struct XtreamSeriesInfoInner: Codable, Sendable {
        var name: String?
        var cover: String?
        var plot: String?
        var cast: String?
        var director: String?
        var genre: String?
        var releaseDate: String?
    }

    struct XtreamEpisode: Codable, Sendable {
        var id: String?
        var episode_num: Int?
        var title: String?
        var container_extension: String?
        var info: XtreamEpisodeInfo?
        var added: String?
        var season: Int?
        var direct_source: String?

        struct XtreamEpisodeInfo: Codable, Sendable {
            var movie_image: String?
            var plot: String?
            var duration: String?
            var releaseDate: String?
        }
    }
}
