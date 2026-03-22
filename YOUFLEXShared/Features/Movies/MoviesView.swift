import SwiftUI

struct MoviesView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.movies.isEmpty {
                EmptyLibraryState(
                    title: "No movies",
                    systemImage: "film",
                    description: "Imported VOD movies stored in SQLite will appear here."
                )
            } else {
                List(model.movies) { movie in
                    NavigationLink {
                        MovieDetailView(model: model, movie: movie)
                    } label: {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            RemoteArtworkView(
                                urlString: movie.posterPath,
                                placeholderSystemImage: "film",
                                size: CGSize(width: 58, height: 84),
                                placeholderTitle: movie.title
                            )

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text(movie.title)
                                    .font(.headline)
                                Text(movie.synopsis ?? "No synopsis yet")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.muted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.Colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Movies")
    }
}
