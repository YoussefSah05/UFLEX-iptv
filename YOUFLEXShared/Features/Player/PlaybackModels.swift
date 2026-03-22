import Foundation

enum PlaybackKind: String, Sendable {
    case live
    case movie
    case episode

    var label: String {
        switch self {
        case .live:
            "Live"
        case .movie:
            "Movie"
        case .episode:
            "Episode"
        }
    }
}

struct PlaybackPresentation: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var streamURL: URL
    var kind: PlaybackKind
    var synopsis: String?
    /// Relative path to local VTT file (from Application Support), for VOD subtitle track.
    var transcriptPath: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        streamURL: URL,
        kind: PlaybackKind,
        synopsis: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.streamURL = streamURL
        self.kind = kind
        self.synopsis = synopsis
        self.transcriptPath = transcriptPath
    }
}

extension PlaybackPresentation {
    init(channel: ChannelRecord) {
        self.init(
            id: channel.id,
            title: channel.title,
            subtitle: channel.category ?? channel.tvgName,
            streamURL: URL(string: channel.streamUrl)!,
            kind: .live
        )
    }

    init(movie: MovieRecord) {
        let year = movie.year.map(String.init)
        self.init(
            id: movie.id,
            title: movie.title,
            subtitle: year ?? movie.genres,
            streamURL: URL(string: movie.streamUrl)!,
            kind: .movie,
            synopsis: movie.synopsis,
            transcriptPath: movie.transcriptPath
        )
    }

    init(episode: EpisodeRecord, seriesTitle: String? = nil) {
        self.init(
            id: episode.id,
            title: episode.title,
            subtitle: [
                seriesTitle,
                "S\(episode.seasonNumber) E\(episode.episodeNumber)"
            ]
            .compactMap { $0 }
            .joined(separator: " · "),
            streamURL: URL(string: episode.streamUrl)!,
            kind: .episode,
            synopsis: episode.synopsis,
            transcriptPath: episode.transcriptPath
        )
    }
}

extension ContinueWatchingItem {
    var playbackPresentation: PlaybackPresentation? {
        guard let streamURL = URL(string: streamUrl) else { return nil }
        guard let playbackKind = PlaybackKind(rawValue: kind) else { return nil }

        return PlaybackPresentation(
            id: contentId,
            title: title,
            subtitle: subtitle,
            streamURL: streamURL,
            kind: playbackKind,
            synopsis: synopsis,
            transcriptPath: nil
        )
    }
}
