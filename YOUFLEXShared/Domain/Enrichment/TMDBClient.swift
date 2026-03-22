import Foundation

enum TMDBClientError: LocalizedError {
    case missingReadAccessToken
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingReadAccessToken:
            "Provide a TMDB read access token to enrich metadata."
        case .invalidResponse:
            "TMDB returned an invalid response."
        case let .requestFailed(statusCode):
            "TMDB request failed with status \(statusCode)."
        }
    }
}

struct TMDBImageConfiguration: Sendable {
    let secureBaseURL: URL
    let posterSizes: [String]
    let backdropSizes: [String]

    func posterURL(path: String?) -> String? {
        imageURL(path: path, preferredSize: "w342", availableSizes: posterSizes)
    }

    func backdropURL(path: String?) -> String? {
        imageURL(path: path, preferredSize: "w780", availableSizes: backdropSizes)
    }

    private func imageURL(path: String?, preferredSize: String, availableSizes: [String]) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return path
        }

        let selectedSize = availableSizes.contains(preferredSize) ? preferredSize : (availableSizes.last ?? "original")
        return secureBaseURL.appendingPathComponent(selectedSize).appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
    }
}

struct TMDBMovieCandidate: Sendable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
}

struct TMDBSeriesCandidate: Sendable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
}

struct TMDBMovieDetails: Sendable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let runtime: Int?
    let genres: String?
    let posterPath: String?
    let backdropPath: String?
}

struct TMDBSeriesDetails: Sendable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let genres: String?
    let status: String?
    let posterPath: String?
    let backdropPath: String?
}

struct TMDBClient: Sendable {
    private let readAccessToken: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    init(readAccessToken: String, session: URLSession = .shared) {
        self.readAccessToken = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func fetchImageConfiguration() async throws -> TMDBImageConfiguration {
        let response: ConfigurationResponse = try await performRequest(path: "/configuration", queryItems: [])
        return TMDBImageConfiguration(
            secureBaseURL: URL(string: response.images.secureBaseUrl)!,
            posterSizes: response.images.posterSizes,
            backdropSizes: response.images.backdropSizes
        )
    }

    func searchMovies(query: String, year: Int?) async throws -> [TMDBMovieCandidate] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }
        let response: MovieSearchResponse = try await performRequest(path: "/search/movie", queryItems: items)
        return response.results.map {
            TMDBMovieCandidate(
                id: $0.id,
                title: $0.title,
                year: Self.year(from: $0.releaseDate),
                overview: $0.overview,
                posterPath: $0.posterPath,
                backdropPath: $0.backdropPath
            )
        }
    }

    func searchSeries(query: String) async throws -> [TMDBSeriesCandidate] {
        let response: SeriesSearchResponse = try await performRequest(
            path: "/search/tv",
            queryItems: [URLQueryItem(name: "query", value: query)]
        )
        return response.results.map {
            TMDBSeriesCandidate(
                id: $0.id,
                title: $0.name,
                year: Self.year(from: $0.firstAirDate),
                overview: $0.overview,
                posterPath: $0.posterPath,
                backdropPath: $0.backdropPath
            )
        }
    }

    func fetchMovieDetails(id: Int) async throws -> TMDBMovieDetails {
        let response: MovieDetailsResponse = try await performRequest(path: "/movie/\(id)", queryItems: [])
        return TMDBMovieDetails(
            id: response.id,
            title: response.title,
            year: Self.year(from: response.releaseDate),
            overview: response.overview,
            runtime: response.runtime,
            genres: response.genres.map(\.name).joined(separator: ", ").nonEmptyValue,
            posterPath: response.posterPath,
            backdropPath: response.backdropPath
        )
    }

    func fetchSeriesDetails(id: Int) async throws -> TMDBSeriesDetails {
        let response: SeriesDetailsResponse = try await performRequest(path: "/tv/\(id)", queryItems: [])
        return TMDBSeriesDetails(
            id: response.id,
            title: response.name,
            year: Self.year(from: response.firstAirDate),
            overview: response.overview,
            genres: response.genres.map(\.name).joined(separator: ", ").nonEmptyValue,
            status: response.status,
            posterPath: response.posterPath,
            backdropPath: response.backdropPath
        )
    }

    private func performRequest<Response: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> Response {
        guard !readAccessToken.isEmpty else {
            throw TMDBClientError.missingReadAccessToken
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = baseURL.path + path
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBClientError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw TMDBClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder.tmdbDecoder.decode(Response.self, from: data)
        } catch {
            throw TMDBClientError.invalidResponse
        }
    }

    private static func year(from dateString: String?) -> Int? {
        guard let dateString, dateString.count >= 4 else {
            return nil
        }
        return Int(dateString.prefix(4))
    }
}

private extension JSONDecoder {
    static let tmdbDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private struct ConfigurationResponse: Decodable {
    struct Images: Decodable {
        let secureBaseUrl: String
        let posterSizes: [String]
        let backdropSizes: [String]
    }

    let images: Images
}

private struct MovieSearchResponse: Decodable {
    let results: [MovieSearchResult]
}

private struct MovieSearchResult: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let releaseDate: String?
    let posterPath: String?
    let backdropPath: String?
}

private struct SeriesSearchResponse: Decodable {
    let results: [SeriesSearchResult]
}

private struct SeriesSearchResult: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
}

private struct MovieDetailsResponse: Decodable {
    struct Genre: Decodable {
        let name: String
    }

    let id: Int
    let title: String
    let overview: String?
    let runtime: Int?
    let releaseDate: String?
    let posterPath: String?
    let backdropPath: String?
    let genres: [Genre]
}

private struct SeriesDetailsResponse: Decodable {
    struct Genre: Decodable {
        let name: String
    }

    let id: Int
    let name: String
    let overview: String?
    let status: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let genres: [Genre]
}

private extension String {
    var nonEmptyValue: String? {
        isEmpty ? nil : self
    }
}
