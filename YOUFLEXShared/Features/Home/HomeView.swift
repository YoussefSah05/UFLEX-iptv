import SwiftUI

struct HomeView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                PanelCard {
                    Text("YOUFLEX")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.Colors.onSurface)
                    Text("Local-first Apple IPTV library.")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.muted)

                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatisticChip(label: "Providers", value: "\(model.summary.providerCount)")
                        StatisticChip(label: "Live", value: "\(model.summary.channelCount)")
                        StatisticChip(label: "Movies", value: "\(model.summary.movieCount)")
                        StatisticChip(label: "Series", value: "\(model.summary.seriesCount)")
                    }
                }

                if model.summary.providerCount == 0 {
                    EmptyLibraryState(
                        title: "Your library is empty",
                        systemImage: "tv.badge.wifi",
                        description: "The native Apple database is ready. Import will populate live, movies, and series here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if !model.continueWatching.isEmpty {
                            PanelCard {
                                Text("Continue Watching")
                                    .font(.headline)

                                ForEach(model.continueWatching.prefix(5)) { item in
                                    if let presentation = item.playbackPresentation {
                                        NavigationLink {
                                            PlayerView(model: model, presentation: presentation)
                                        } label: {
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                                    Text(item.title)
                                                        .font(.headline)
                                                        .foregroundStyle(AppTheme.Colors.onSurface)
                                                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                                                        Text(subtitle)
                                                            .font(.subheadline)
                                                            .foregroundStyle(AppTheme.Colors.muted)
                                                    }
                                                }
                                                Spacer()
                                                ProgressPill(
                                                    text: ProgressTracker.progressText(
                                                        positionMs: item.positionMs,
                                                        durationMs: item.durationMs,
                                                        completed: false
                                                    )
                                                )
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Text("Recent catalog snapshot")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.onBackground)

                        if !model.channels.isEmpty {
                            PanelCard {
                                Text("Live")
                                    .font(.headline)
                                ForEach(model.channels.prefix(3)) { channel in
                                    NavigationLink(channel.title) {
                                        PlayerView(model: model, presentation: PlaybackPresentation(channel: channel))
                                    }
                                    .foregroundStyle(AppTheme.Colors.muted)
                                }
                            }
                        }

                        if !model.movies.isEmpty {
                            PanelCard {
                                Text("Movies")
                                    .font(.headline)
                                ForEach(model.movies.prefix(3)) { movie in
                                    NavigationLink(movie.title) {
                                        MovieDetailView(model: model, movie: movie)
                                    }
                                    .foregroundStyle(AppTheme.Colors.muted)
                                }
                            }
                        }

                        if !model.series.isEmpty {
                            PanelCard {
                                Text("Series")
                                    .font(.headline)
                                ForEach(model.series.prefix(3)) { series in
                                    NavigationLink(series.title) {
                                        SeriesDetailView(model: model, series: series)
                                    }
                                    .foregroundStyle(AppTheme.Colors.muted)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    model.refresh()
                }
            }
        }
    }
}
