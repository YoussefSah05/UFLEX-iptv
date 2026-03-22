import XCTest
@testable import YOUFLEXiOS

final class MetadataConfidenceScorerTests: XCTestCase {
    func testExactMovieMatchScoresHigh() {
        let score = MetadataConfidenceScorer.movieScore(
            importedTitle: "Inception",
            importedYear: 2010,
            candidateTitle: "Inception",
            candidateYear: 2010
        )

        XCTAssertGreaterThanOrEqual(score, 0.95)
    }

    func testYearMismatchPenalizesMovieScore() {
        let score = MetadataConfidenceScorer.movieScore(
            importedTitle: "Inception",
            importedYear: 2010,
            candidateTitle: "Inception",
            candidateYear: 2016
        )

        XCTAssertLessThan(score, 0.8)
    }

    func testSeriesNormalizationHandlesPunctuationAndCase() {
        let score = MetadataConfidenceScorer.seriesScore(
            importedTitle: "Breakpoint: Reloaded",
            candidateTitle: "breakpoint reloaded",
            candidateYear: 2024
        )

        XCTAssertGreaterThanOrEqual(score, 0.78)
    }
}
