import SwiftUI

struct DownloadsView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.downloads.isEmpty {
                EmptyLibraryState(
                    title: "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: "Start a download from any movie or episode player to keep a local copy."
                )
                .padding(AppTheme.Spacing.lg)
            } else {
                List(model.downloads) { download in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text(download.title)
                                    .font(.headline)
                                Text(download.contentType.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.muted)
                            }
                            Spacer()
                            ProgressPill(text: statusLabel(for: download))
                        }

                        if let message = download.failureMessage, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else if download.expectedBytes > 0, download.status != "completed" {
                            let progress = Double(download.bytesDownloaded) / Double(download.expectedBytes)
                            ProgressView(value: progress)
                        }

                        if let presentation = model.playbackPresentation(for: download), download.status == "completed" {
                            NavigationLink {
                                PlayerView(model: model, presentation: presentation)
                            } label: {
                                Label("Play Offline", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .listRowBackground(AppTheme.Colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    model.refresh()
                }
            }
        }
    }

    private func statusLabel(for download: DownloadRecord) -> String {
        switch download.status {
        case "completed":
            return "Ready"
        case "failed":
            return "Failed"
        case "downloading":
            return "Downloading"
        default:
            return download.status.capitalized
        }
    }
}
