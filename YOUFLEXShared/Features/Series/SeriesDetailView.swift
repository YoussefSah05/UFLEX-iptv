import SwiftUI

struct SeriesDetailView: View {
    let model: AppModel
    let series: SeriesRecord
    @State private var episodes: [EpisodeRecord] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                        RemoteArtworkView(
                            urlString: series.posterPath,
                            placeholderSystemImage: "square.stack.3d.up",
                            size: CGSize(width: 112, height: 164)
                        )

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text(series.title)
                                .font(.title2.weight(.bold))
                            Text(summaryLine)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.muted)

                            if let synopsis = series.synopsis, !synopsis.isEmpty {
                                Text(synopsis)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.muted)
                            }

                            StatisticChip(label: "Metadata", value: series.enrichmentStatus.capitalized)
                        }
                    }

                    if let target = model.nextEpisodeTarget(for: series, episodes: episodes) {
                        NavigationLink {
                            PlayerView(
                                model: model,
                                presentation: PlaybackPresentation(
                                    episode: target.episode,
                                    seriesTitle: series.title
                                )
                            )
                        } label: {
                            Label(target.mode.actionTitle, systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if let progress = target.progress {
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
                .padding(.vertical, AppTheme.Spacing.xs)
                .listRowBackground(AppTheme.Colors.surface)
            }

            Section("Episodes") {
                if episodes.isEmpty {
                    Text("No episodes have been imported for this series yet.")
                        .foregroundStyle(AppTheme.Colors.muted)
                        .listRowBackground(AppTheme.Colors.surface)
                } else {
                    ForEach(episodes) { episode in
                        NavigationLink {
                            PlayerView(
                                model: model,
                                presentation: PlaybackPresentation(
                                    episode: episode,
                                    seriesTitle: series.title
                                )
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("S\(episode.seasonNumber) · E\(episode.episodeNumber)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.muted)
                                Text(episode.title)
                                    .font(.headline)
                                Text("Transcript: \(episode.transcriptStatus.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.muted)
                                if let progress = model.episodeProgress(for: episode) {
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
                        .listRowBackground(AppTheme.Colors.surface)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle(series.title)
        .youflexInlineTitleMode()
        .task(id: series.id) {
            episodes = model.episodes(for: series)
        }
    }

    private var summaryLine: String {
        "\(series.totalSeasons) seasons · \(series.totalEpisodes) episodes"
    }
}
