import SwiftUI

struct LiveView: View {
    let model: AppModel

    var body: some View {
        content
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Live")
    }

    @ViewBuilder
    private var content: some View {
        if model.channels.isEmpty {
            EmptyLibraryState(
                title: "No live channels",
                systemImage: "dot.radiowaves.left.and.right",
                description: "Channels imported into the local SQLite library will appear here."
            )
        } else {
            List(model.channels) { channel in
                NavigationLink {
                    PlayerView(model: model, presentation: PlaybackPresentation(channel: channel))
                } label: {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        RemoteArtworkView(
                            urlString: channel.logoUrl,
                            placeholderSystemImage: "dot.radiowaves.left.and.right",
                            size: CGSize(width: 58, height: 58),
                            cornerRadius: AppTheme.Corner.button,
                            placeholderTitle: channel.title
                        )

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(channel.title)
                                .font(.headline)
                            Text(channel.category ?? "Uncategorised")
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
}
