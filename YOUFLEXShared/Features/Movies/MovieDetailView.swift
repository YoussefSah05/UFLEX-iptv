import SwiftUI

struct MovieDetailView: View {
    let model: AppModel
    let movie: MovieRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                PanelCard {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                        RemoteArtworkView(
                            urlString: movie.posterPath,
                            placeholderSystemImage: "film",
                            size: CGSize(width: 120, height: 178),
                            placeholderTitle: movie.title
                        )

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text(movie.title)
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(AppTheme.Colors.onSurface)

                            Text(metadataLine)
                                .font(.headline)
                                .foregroundStyle(AppTheme.Colors.muted)

                            if let progress = model.movieProgress(for: movie) {
                                ProgressPill(
                                    text: ProgressTracker.progressText(
                                        positionMs: progress.positionMs,
                                        durationMs: progress.durationMs,
                                        completed: progress.completed
                                    )
                                )
                            }
                        }
                    }

                    if let synopsis = movie.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.body)
                            .foregroundStyle(AppTheme.Colors.muted)
                    } else {
                        Text("No synopsis has been imported yet.")
                            .font(.body)
                            .foregroundStyle(AppTheme.Colors.muted)
                    }

                    NavigationLink {
                        PlayerView(model: model, presentation: PlaybackPresentation(movie: movie))
                    } label: {
                        Label(primaryActionTitle, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatisticChip(label: "Transcript", value: transcriptLabel)
                        if let download = model.downloadRecord(for: PlaybackPresentation(movie: movie)) {
                            StatisticChip(label: "Download", value: download.status.capitalized)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle(movie.title)
        .youflexInlineTitleMode()
    }

    private var metadataLine: String {
        [
            movie.year.map(String.init),
            movie.runtime.map { "\($0)m" },
            movie.genres
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var primaryActionTitle: String {
        guard let progress = model.movieProgress(for: movie) else {
            return "Play Movie"
        }

        return ProgressTracker.resumePositionMs(
            positionMs: progress.positionMs,
            durationMs: progress.durationMs,
            completed: progress.completed
        ) > 0 ? "Resume Movie" : "Play Movie"
    }

    private var transcriptLabel: String {
        movie.transcriptStatus == "ready" ? "Ready" : movie.transcriptStatus.capitalized
    }
}
