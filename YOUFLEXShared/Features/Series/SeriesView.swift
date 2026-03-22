import SwiftUI

struct SeriesView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.series.isEmpty {
                EmptyLibraryState(
                    title: "No series",
                    systemImage: "square.stack.3d.up",
                    description: "Imported episodic content stored in SQLite will appear here."
                )
            } else {
                List(model.series) { series in
                    NavigationLink {
                        SeriesDetailView(model: model, series: series)
                    } label: {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            RemoteArtworkView(
                                urlString: series.posterPath,
                                placeholderSystemImage: "square.stack.3d.up",
                                size: CGSize(width: 58, height: 84)
                            )

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text(series.title)
                                    .font(.headline)
                                Text("\(series.totalSeasons) seasons · \(series.totalEpisodes) episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.muted)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.Colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Series")
    }
}
