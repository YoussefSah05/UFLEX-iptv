import Foundation

struct LibraryEnrichmentSummary: Sendable {
    var moviesUpdated: Int = 0
    var seriesUpdated: Int = 0
    var unmatchedMovies: Int = 0
    var unmatchedSeries: Int = 0
}

struct LibraryEnrichmentCoordinator {
    private let database: AppDatabase
    private let client: TMDBClient

    init(database: AppDatabase, client: TMDBClient) {
        self.database = database
        self.client = client
    }

    func enrichPendingLibrary(movieLimit: Int = 20, seriesLimit: Int = 20) async throws -> LibraryEnrichmentSummary {
        let imageConfiguration = try await client.fetchImageConfiguration()
        var summary = LibraryEnrichmentSummary()

        for movie in try database.fetchMoviesNeedingEnrichment(limit: movieLimit) {
            if let enrichment = try await enrich(movie: movie, imageConfiguration: imageConfiguration) {
                try database.applyMovieEnrichment(enrichment)
                summary.moviesUpdated += 1
            } else {
                try database.markMovieEnrichmentUnmatched(movieId: movie.id)
                summary.unmatchedMovies += 1
            }
        }

        for series in try database.fetchSeriesNeedingEnrichment(limit: seriesLimit) {
            if let enrichment = try await enrich(series: series, imageConfiguration: imageConfiguration) {
                try database.applySeriesEnrichment(enrichment)
                summary.seriesUpdated += 1
            } else {
                try database.markSeriesEnrichmentUnmatched(seriesId: series.id)
                summary.unmatchedSeries += 1
            }
        }

        return summary
    }

    private func enrich(movie: MovieRecord, imageConfiguration: TMDBImageConfiguration) async throws -> MovieEnrichmentUpdate? {
        let candidates = try await client.searchMovies(query: movie.title, year: movie.year)
        guard let bestCandidate = candidates
            .map({ candidate in
                (candidate, MetadataConfidenceScorer.movieScore(
                    importedTitle: movie.title,
                    importedYear: movie.year,
                    candidateTitle: candidate.title,
                    candidateYear: candidate.year
                ))
            })
            .max(by: { $0.1 < $1.1 }),
              bestCandidate.1 >= 0.85 else {
            return nil
        }

        let details = try await client.fetchMovieDetails(id: bestCandidate.0.id)
        let posterURLString = imageConfiguration.posterURL(path: details.posterPath ?? bestCandidate.0.posterPath)
        let backdropURLString = imageConfiguration.backdropURL(path: details.backdropPath ?? bestCandidate.0.backdropPath)
        var posterPath = movie.posterPath
        var backdropPath = movie.backdropPath
        if let urlString = posterURLString, let url = URL(string: urlString) {
            posterPath = try await ArtworkCache.downloadAndCachePoster(url: url, contentType: "movie", contentId: movie.id) ?? posterPath
        }
        if let urlString = backdropURLString, let url = URL(string: urlString) {
            backdropPath = try await ArtworkCache.downloadAndCacheBackdrop(url: url, contentType: "movie", contentId: movie.id) ?? backdropPath
        }
        return MovieEnrichmentUpdate(
            movieId: movie.id,
            tmdbId: details.id,
            posterPath: posterPath,
            backdropPath: backdropPath,
            synopsis: details.overview ?? bestCandidate.0.overview ?? movie.synopsis,
            genres: details.genres ?? movie.genres,
            runtime: details.runtime ?? movie.runtime,
            year: details.year ?? movie.year,
            enrichmentStatus: bestCandidate.1 >= 0.86 ? "ready" : "needs_review"
        )
    }

    private func enrich(series: SeriesRecord, imageConfiguration: TMDBImageConfiguration) async throws -> SeriesEnrichmentUpdate? {
        let candidates = try await client.searchSeries(query: series.title)
        guard let bestCandidate = candidates
            .map({ candidate in
                (candidate, MetadataConfidenceScorer.seriesScore(
                    importedTitle: series.title,
                    candidateTitle: candidate.title,
                    candidateYear: candidate.year
                ))
            })
            .max(by: { $0.1 < $1.1 }),
              bestCandidate.1 >= 0.85 else {
            return nil
        }

        let details = try await client.fetchSeriesDetails(id: bestCandidate.0.id)
        let posterURLString = imageConfiguration.posterURL(path: details.posterPath ?? bestCandidate.0.posterPath)
        let backdropURLString = imageConfiguration.backdropURL(path: details.backdropPath ?? bestCandidate.0.backdropPath)
        var posterPath = series.posterPath
        var backdropPath = series.backdropPath
        if let urlString = posterURLString, let url = URL(string: urlString) {
            posterPath = try await ArtworkCache.downloadAndCachePoster(url: url, contentType: "series", contentId: series.id) ?? posterPath
        }
        if let urlString = backdropURLString, let url = URL(string: urlString) {
            backdropPath = try await ArtworkCache.downloadAndCacheBackdrop(url: url, contentType: "series", contentId: series.id) ?? backdropPath
        }
        return SeriesEnrichmentUpdate(
            seriesId: series.id,
            tmdbId: details.id,
            posterPath: posterPath,
            backdropPath: backdropPath,
            synopsis: details.overview ?? bestCandidate.0.overview ?? series.synopsis,
            genres: details.genres ?? series.genres,
            status: details.status ?? series.status,
            enrichmentStatus: bestCandidate.1 >= 0.86 ? "ready" : "needs_review"
        )
    }
}
