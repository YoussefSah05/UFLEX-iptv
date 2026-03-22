import SwiftUI

struct SearchResultDestinationView: View {
    let model: AppModel
    let result: SearchResultItem

    var body: some View {
        Group {
            switch result.kind {
            case "channel":
                if let channel = model.channel(id: result.id) {
                    PlayerView(model: model, presentation: PlaybackPresentation(channel: channel))
                } else {
                    missingState
                }
            case "movie":
                if let movie = model.movie(id: result.id) {
                    MovieDetailView(model: model, movie: movie)
                } else {
                    missingState
                }
            case "series":
                if let series = model.series(id: result.id) {
                    SeriesDetailView(model: model, series: series)
                } else {
                    missingState
                }
            default:
                missingState
            }
        }
    }

    private var missingState: some View {
        EmptyLibraryState(
            title: "Content unavailable",
            systemImage: "exclamationmark.triangle",
            description: "The selected item could not be resolved from the local database."
        )
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }
}
