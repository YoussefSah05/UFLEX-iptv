import Foundation

/// Named stages of the M3U import pipeline.
enum ImportPipelineStage: String, Sendable, CaseIterable {
    case fetching = "Fetching"
    case parsing = "Parsing"
    case classifying = "Classifying"
    case deduplicating = "Deduplicating"
    case enriching = "Enriching"
    case indexing = "Indexing"
}

/// Progress snapshot for the import pipeline, reported for UI display.
struct ImportPipelineProgress: Sendable, Equatable {
    var stage: ImportPipelineStage
    var linesRead: Int
    var parsedCount: Int
    var classifiedLive: Int
    var classifiedMovie: Int
    var classifiedSeries: Int
    var classifiedUncertain: Int
    var dedupSkipped: Int
    var enrichedCount: Int
    var failedCount: Int
    var estimatedSecondsRemaining: Int?

    static func initial(stage: ImportPipelineStage = .fetching) -> ImportPipelineProgress {
        ImportPipelineProgress(
            stage: stage,
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
    }

    var totalClassified: Int {
        classifiedLive + classifiedMovie + classifiedSeries + classifiedUncertain
    }
}
