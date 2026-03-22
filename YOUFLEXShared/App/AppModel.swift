import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var summary: LibrarySummary = .empty
    var providers: [ProviderRecord] = []
    var channels: [ChannelRecord] = []
    var movies: [MovieRecord] = []
    var series: [SeriesRecord] = []
    var downloads: [DownloadRecord] = []
    var continueWatching: [ContinueWatchingItem] = []
    var movieProgressByID: [String: MovieProgressRecord] = [:]
    var episodeProgressByID: [String: EpisodeProgressRecord] = [:]
    var searchQuery = ""
    var searchResults: [SearchResultItem] = []
    var tmdbReadAccessToken = TMDBSettings.loadReadAccessToken()
    var preferredWhisperModel = TranscriptionSettings.loadPreferredModel()
    var lastError: String?
    var importStatusMessage: String?
    var epgStatusMessage: String?
    var enrichmentStatusMessage: String?
    var transcriptionStatusMessage: String?
    var downloadStatusMessage: String?
    var isImporting = false
    var importPipelineProgress: ImportPipelineProgress?
    var isLoadingEPG = false
    var isEnriching = false
    var isTranscribingLibrary = false

    @ObservationIgnored let database: AppDatabase
    @ObservationIgnored private let transcriptionCoordinator: LibraryTranscriptionCoordinator
    @ObservationIgnored private let downloadManager: OfflineDownloadManager
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init(database: AppDatabase = .shared) {
        self.database = database
        self.transcriptionCoordinator = LibraryTranscriptionCoordinator(database: database)
        self.downloadManager = OfflineDownloadManager(database: database)
        notificationTokens = [
            NotificationCenter.default.addObserver(forName: .youflexLibraryDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            },
            NotificationCenter.default.addObserver(forName: .youflexDownloadsDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        ]
        refresh()
    }

    func refresh() {
        do {
            summary = try database.fetchLibrarySummary()
            providers = try database.fetchProviders()
            channels = try database.fetchChannels()
            movies = try database.fetchMovies()
            series = try database.fetchSeries()
            downloads = try database.fetchDownloads()
            continueWatching = try database.fetchContinueWatching()
            movieProgressByID = Dictionary(
                uniqueKeysWithValues: try database.fetchMovieProgress().map { ($0.movieId, $0) }
            )
            episodeProgressByID = Dictionary(
                uniqueKeysWithValues: try database.fetchEpisodeProgress().map { ($0.episodeId, $0) }
            )
            if !searchQuery.isEmpty {
                searchResults = try database.searchCatalog(searchQuery)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importPlaylist(name: String, urlString: String, pastedContent: String) async {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlaylist = pastedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        let source: ProviderImportSource
        if !trimmedPlaylist.isEmpty {
            source = .pasted(trimmedPlaylist)
        } else if let url = URL(string: trimmedURLString) {
            source = .remote(url)
        } else {
            importStatusMessage = "Provide either a valid M3U URL or playlist text."
            return
        }

        isImporting = true
        importStatusMessage = nil
        importPipelineProgress = nil

        do {
            let summary = try await M3UImportCoordinator(database: database)
                .importProvider(name: name, source: source) { [weak self] progress in
                    self?.importPipelineProgress = progress
                }
            refresh()
            importStatusMessage = """
            Imported \(summary.providerName): \(summary.channels) live, \(summary.movies) movies, \(summary.series) series, \(summary.episodes) episodes.
            """
        } catch {
            importStatusMessage = error.localizedDescription
        }

        isImporting = false
        importPipelineProgress = nil
    }

    func importXtreamProvider(name: String, serverURLString: String, username: String, password: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedURL.isEmpty, !trimmedUser.isEmpty, !trimmedPass.isEmpty else {
            importStatusMessage = "Provide provider name, server URL, username, and password."
            return
        }

        guard let serverURL = URL(string: trimmedURL),
              serverURL.scheme == "http" || serverURL.scheme == "https" else {
            importStatusMessage = "Invalid Xtream server URL."
            return
        }

        isImporting = true
        importStatusMessage = nil

        do {
            let summary = try await XtreamImportCoordinator(database: database)
                .importProvider(name: trimmedName, serverURL: serverURL, username: trimmedUser, password: trimmedPass)

            try KeychainManager.saveXtreamCredentials(
                username: trimmedUser,
                password: trimmedPass,
                providerId: summary.providerId
            )

            refresh()
            importStatusMessage = """
            Imported \(summary.providerName): \(summary.channels) live, \(summary.movies) movies, \(summary.series) series, \(summary.episodes) episodes.
            """
        } catch {
            importStatusMessage = error.localizedDescription
        }

        isImporting = false
    }

    func loadEPG(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else {
            epgStatusMessage = "Provide a valid XMLTV URL."
            return
        }

        isLoadingEPG = true
        epgStatusMessage = nil

        do {
            let result = try await XMLTVParser().parse(contentsOf: url)
            let count = try database.applyEPG(result: result)
            refresh()
            epgStatusMessage = "Loaded \(count) EPG programmes."
        } catch {
            epgStatusMessage = error.localizedDescription
        }

        isLoadingEPG = false
    }

    func persistTMDBReadAccessToken() {
        TMDBSettings.saveReadAccessToken(tmdbReadAccessToken)
        tmdbReadAccessToken = TMDBSettings.loadReadAccessToken()
    }

    func persistPreferredWhisperModel() {
        TranscriptionSettings.savePreferredModel(preferredWhisperModel)
        preferredWhisperModel = TranscriptionSettings.loadPreferredModel()
    }

    func enrichPendingMetadata() async {
        let trimmedToken = tmdbReadAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            enrichmentStatusMessage = "Provide a TMDB read access token to enrich movies and series."
            return
        }

        isEnriching = true
        enrichmentStatusMessage = nil
        persistTMDBReadAccessToken()

        do {
            let summary = try await LibraryEnrichmentCoordinator(
                database: database,
                client: TMDBClient(readAccessToken: trimmedToken)
            )
            .enrichPendingLibrary()
            refresh()
            enrichmentStatusMessage = """
            Enriched \(summary.moviesUpdated) movies and \(summary.seriesUpdated) series. \
            Unmatched: \(summary.unmatchedMovies) movies, \(summary.unmatchedSeries) series.
            """
        } catch {
            enrichmentStatusMessage = error.localizedDescription
        }

        isEnriching = false
    }

    func updateSearch(query: String) {
        searchQuery = query
        do {
            searchResults = try database.searchCatalog(query)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func movie(id: String) -> MovieRecord? {
        do {
            return try database.fetchMovie(id: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func channel(id: String) -> ChannelRecord? {
        do {
            return try database.fetchChannel(id: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func series(id: String) -> SeriesRecord? {
        do {
            return try database.fetchSeries(id: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func episodes(for series: SeriesRecord, limit: Int? = nil) -> [EpisodeRecord] {
        do {
            return try database.fetchEpisodes(seriesId: series.id, limit: limit)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func movieProgress(for movie: MovieRecord) -> MovieProgressRecord? {
        movieProgressByID[movie.id]
    }

    func episodeProgress(for episode: EpisodeRecord) -> EpisodeProgressRecord? {
        episodeProgressByID[episode.id]
    }

    func transcriptSegments(for presentation: PlaybackPresentation) -> [TranscriptSegmentRecord] {
        guard let contentType = presentation.transcriptContentType else {
            return []
        }

        do {
            return try database.fetchTranscriptSegments(contentId: presentation.id, contentType: contentType.rawValue)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func transcriptStatus(for presentation: PlaybackPresentation) -> String {
        switch presentation.kind {
        case .live:
            return "unsupported"
        case .movie:
            return movie(id: presentation.id)?.transcriptStatus ?? "none"
        case .episode:
            return tryFetchEpisode(id: presentation.id)?.transcriptStatus ?? "none"
        }
    }

    func downloadRecord(for presentation: PlaybackPresentation) -> DownloadRecord? {
        do {
            if let completed = try database.fetchCompletedDownload(contentId: presentation.id, contentType: presentation.kind.rawValue) {
                return completed
            }
            return try database.fetchDownload(id: OfflineDownloadManager.downloadIdentifier(for: presentation))
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func localFileURL(for download: DownloadRecord) -> URL? {
        guard let localRelativePath = download.localRelativePath else {
            return nil
        }
        return try? AppPaths.resolvedURL(for: localRelativePath)
    }

    func resolvedPlaybackURL(for presentation: PlaybackPresentation) -> URL {
        guard let download = downloadRecord(for: presentation),
              download.status == "completed",
              let localURL = localFileURL(for: download),
              FileManager.default.fileExists(atPath: localURL.path) else {
            return presentation.streamURL
        }
        return localURL
    }

    func playbackPresentation(for download: DownloadRecord) -> PlaybackPresentation? {
        switch download.contentType {
        case PlaybackKind.movie.rawValue:
            guard let movie = movie(id: download.contentId) else { return nil }
            var presentation = PlaybackPresentation(movie: movie)
            presentation.streamURL = resolvedPlaybackURL(for: presentation)
            return presentation
        case PlaybackKind.episode.rawValue:
            guard let episode = tryFetchEpisode(id: download.contentId) else { return nil }
            let seriesTitle: String?
            do {
                seriesTitle = try database.fetchSeries(id: episode.seriesId)?.title
            } catch {
                seriesTitle = nil
            }
            var presentation = PlaybackPresentation(episode: episode, seriesTitle: seriesTitle)
            presentation.streamURL = resolvedPlaybackURL(for: presentation)
            return presentation
        default:
            return nil
        }
    }

    func generateTranscript(for presentation: PlaybackPresentation) async {
        transcriptionStatusMessage = nil
        persistPreferredWhisperModel()

        do {
            let segmentCount = try await transcriptionCoordinator.transcribe(
                presentation: presentation,
                preferredModel: preferredWhisperModel
            )
            refresh()
            transcriptionStatusMessage = "Generated \(segmentCount) transcript segments for \(presentation.title)."
        } catch {
            refresh()
            transcriptionStatusMessage = error.localizedDescription
        }
    }

    func transcribePendingLibrary() async {
        isTranscribingLibrary = true
        transcriptionStatusMessage = nil
        persistPreferredWhisperModel()

        let summary = await transcriptionCoordinator.transcribePendingLibrary(preferredModel: preferredWhisperModel)
        refresh()
        transcriptionStatusMessage = """
        Transcribed \(summary.moviesTranscribed) movies and \(summary.episodesTranscribed) episodes. \
        Failures: \(summary.failures).
        """
        isTranscribingLibrary = false
    }

    func startDownload(for presentation: PlaybackPresentation) async {
        downloadStatusMessage = nil

        do {
            try await downloadManager.startDownload(for: presentation)
            refresh()
            downloadStatusMessage = "Started download for \(presentation.title)."
        } catch {
            downloadStatusMessage = error.localizedDescription
        }
    }

    func nextEpisodeTarget(for series: SeriesRecord, episodes: [EpisodeRecord]? = nil) -> SeriesPlaybackTarget? {
        let seriesEpisodes = episodes ?? self.episodes(for: series)
        return NextEpisodeResolver.resolve(
            episodes: seriesEpisodes,
            progressByEpisodeID: episodeProgressByID
        )
    }

    func resumePosition(for presentation: PlaybackPresentation) -> Int64 {
        switch presentation.kind {
        case .live:
            return 0
        case .movie:
            guard let progress = movieProgressByID[presentation.id] else { return 0 }
            return ProgressTracker.resumePositionMs(
                positionMs: progress.positionMs,
                durationMs: progress.durationMs,
                completed: progress.completed
            )
        case .episode:
            guard let progress = episodeProgressByID[presentation.id] else { return 0 }
            return ProgressTracker.resumePositionMs(
                positionMs: progress.positionMs,
                durationMs: progress.durationMs,
                completed: progress.completed
            )
        }
    }

    func recordProgress(for presentation: PlaybackPresentation, positionMs: Int64, durationMs: Int64) {
        guard ProgressTracker.shouldPersist(positionMs: positionMs, durationMs: durationMs) else { return }

        let now = Date()
        let watchedPercent = ProgressTracker.watchedPercent(positionMs: positionMs, durationMs: durationMs)
        let completed = ProgressTracker.isCompleted(positionMs: positionMs, durationMs: durationMs)

        do {
            switch presentation.kind {
            case .live:
                return
            case .movie:
                let progress = MovieProgressRecord(
                    movieId: presentation.id,
                    positionMs: positionMs,
                    durationMs: durationMs,
                    watchedPercent: watchedPercent,
                    completed: completed,
                    lastWatchedAt: now
                )
                try database.saveMovieProgress(progress)
                movieProgressByID[presentation.id] = progress
            case .episode:
                if let episode = try database.fetchEpisode(id: presentation.id) {
                    let progress = EpisodeProgressRecord(
                        episodeId: episode.id,
                        seriesId: episode.seriesId,
                        seasonNumber: episode.seasonNumber,
                        episodeNumber: episode.episodeNumber,
                        positionMs: positionMs,
                        durationMs: durationMs,
                        watchedPercent: watchedPercent,
                        completed: completed,
                        lastWatchedAt: now
                    )
                    try database.saveEpisodeProgress(progress)
                    episodeProgressByID[presentation.id] = progress
                }
            }
        } catch {
            lastError = error.localizedDescription
            return
        }

        do {
            continueWatching = try database.fetchContinueWatching()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func tryFetchEpisode(id: String) -> EpisodeRecord? {
        do {
            return try database.fetchEpisode(id: id)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
