import SwiftUI

struct SearchView: View {
    let model: AppModel
    @State private var query = ""

    var body: some View {
        Group {
            if query.count < 2 {
                EmptyLibraryState(
                    title: "Search your local library",
                    systemImage: "magnifyingglass",
                    description: "Search runs against SQLite FTS tables once your catalog is imported."
                )
            } else if model.searchResults.isEmpty {
                EmptyLibraryState(
                    title: "No results",
                    systemImage: "magnifyingglass",
                    description: "No local content matched “\(query)”."
                )
            } else {
                List(model.searchResults) { result in
                    NavigationLink {
                        SearchResultDestinationView(model: model, result: result)
                    } label: {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.kind.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.muted)
                        }
                    }
                    .listRowBackground(AppTheme.Colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search channels, movies, series")
        .onChange(of: query) { _, newValue in
            model.updateSearch(query: newValue)
        }
    }
}
