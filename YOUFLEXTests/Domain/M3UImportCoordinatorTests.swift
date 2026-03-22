import XCTest
@testable import YOUFLEXiOS

final class M3UImportCoordinatorTests: XCTestCase {
    func testParserResolvesRelativeURLsAndCleansTitles() {
        let parser = M3UParser()
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="news.one" group-title="News",group-logo="https://img.example.com/logo.png" World News HD
        live/world-news.m3u8
        """

        let entries = parser.parse(playlist, baseURL: URL(string: "https://provider.example.com/catalog/main.m3u")!)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "World News HD")
        XCTAssertEqual(entries[0].streamURL.absoluteString, "https://provider.example.com/catalog/live/world-news.m3u8")
        XCTAssertEqual(entries[0].groupTitle, "News")
    }

    @MainActor
    func testImportCoordinatorPersistsChannelsMoviesAndSeries() async throws {
        let database = try AppDatabase.makeInMemory()
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="world.news" tvg-name="World News" group-title="News",World News HD
        https://streams.example.com/live/world-news.m3u8
        #EXTINF:7200 group-title="Movies",Inception (2010)
        https://streams.example.com/movies/inception.mp4
        #EXTINF:3600 group-title="Series",Breakpoint S02E03 - Fault Line
        https://streams.example.com/series/breakpoint-s02e03.mkv
        """

        let coordinator = M3UImportCoordinator(database: database)
        let summary = try await coordinator.importProvider(
            name: "Personal Playlist",
            source: .pasted(playlist)
        )

        XCTAssertEqual(summary.channels, 1)
        XCTAssertEqual(summary.movies, 1)
        XCTAssertEqual(summary.series, 1)
        XCTAssertEqual(summary.episodes, 1)

        let providers = try database.fetchProviders()
        let channels = try database.fetchChannels()
        let movies = try database.fetchMovies()
        let series = try database.fetchSeries()

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(channels.first?.streamUrl, "https://streams.example.com/live/world-news.m3u8")
        XCTAssertEqual(movies.first?.streamUrl, "https://streams.example.com/movies/inception.mp4")
        XCTAssertEqual(movies.first?.year, 2010)
        XCTAssertEqual(series.first?.title, "Breakpoint")

        let episode = try await database.dbQueue.read { db in
            try EpisodeRecord.fetchOne(db, sql: "SELECT * FROM episode LIMIT 1")
        }
        XCTAssertEqual(episode?.streamUrl, "https://streams.example.com/series/breakpoint-s02e03.mkv")
        XCTAssertEqual(episode?.seasonNumber, 2)
        XCTAssertEqual(episode?.episodeNumber, 3)

        let searchResults = try database.searchCatalog("inception")
        XCTAssertTrue(searchResults.contains(where: { $0.kind == "movie" }))
    }
}
