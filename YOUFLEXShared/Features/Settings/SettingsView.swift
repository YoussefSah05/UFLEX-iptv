import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var providerName = ""

    private var importButtonLabel: String {
        model.isImporting ? "Importing..." : "Import M3U"
    }
    @State private var playlistURL = ""
    @State private var playlistText = ""
    @State private var xtreamServerURL = ""
    @State private var xtreamUsername = ""
    @State private var xtreamPassword = ""
    @State private var epgURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                PanelCard {
                    Text("Native runtime")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.onSurface)
                    Text("The active implementation target is SwiftUI + AVPlayer + GRDB + WhisperKit.")
                        .foregroundStyle(AppTheme.Colors.muted)
                }

                PanelCard {
                    Text("Local database")
                        .font(.headline)
                    Text(model.database.databasePath)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppTheme.Colors.muted)
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("TMDB enrichment")
                            .font(.headline)

                        SecureField("TMDB read access token", text: $model.tmdbReadAccessToken)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexSecretFieldInput()

                        Text("Stored securely in the system Keychain. Never written to the database or files.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.muted)

                        HStack(spacing: AppTheme.Spacing.sm) {
                            Button("Save Token") {
                                model.persistTMDBReadAccessToken()
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task {
                                    await model.enrichPendingMetadata()
                                }
                            } label: {
                                HStack {
                                    if model.isEnriching {
                                        ProgressView()
                                            .tint(AppTheme.Colors.onSurface)
                                    }
                                    Text(model.isEnriching ? "Enriching..." : "Enrich Pending Metadata")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.Colors.accent)
                            .disabled(model.isEnriching || model.tmdbReadAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let enrichmentStatusMessage = model.enrichmentStatusMessage {
                            Text(enrichmentStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.muted)
                        }
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Local transcription")
                            .font(.headline)

                        TextField("Preferred WhisperKit model (optional)", text: $model.preferredWhisperModel)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexProviderNameInput()

                        Text("Leave this empty to let WhisperKit choose the recommended on-device model. Models are stored locally in Application Support.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.muted)

                        HStack(spacing: AppTheme.Spacing.sm) {
                            Button("Save Model Preference") {
                                model.persistPreferredWhisperModel()
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task {
                                    await model.transcribePendingLibrary()
                                }
                            } label: {
                                HStack {
                                    if model.isTranscribingLibrary {
                                        ProgressView()
                                            .tint(AppTheme.Colors.onSurface)
                                    }
                                    Text(model.isTranscribingLibrary ? "Transcribing..." : "Transcribe Pending VOD")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.Colors.accent)
                            .disabled(model.isTranscribingLibrary)
                        }

                        if let transcriptionStatusMessage = model.transcriptionStatusMessage {
                            Text(transcriptionStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.muted)
                        }
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("EPG (Electronic Programme Guide)")
                            .font(.headline)

                        TextField("XMLTV URL", text: $epgURL)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexURLFieldInput()

                        Button {
                            Task {
                                await model.loadEPG(urlString: epgURL)
                            }
                        } label: {
                            HStack {
                                if model.isLoadingEPG {
                                    ProgressView()
                                        .tint(AppTheme.Colors.onSurface)
                                }
                                Text(model.isLoadingEPG ? "Loading..." : "Load EPG")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                        .disabled(model.isLoadingEPG || epgURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let epgStatusMessage = model.epgStatusMessage {
                            Text(epgStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.muted)
                        }
                    }
                }

                PanelCard {
                    Text("Current library")
                        .font(.headline)
                    HStack(spacing: AppTheme.Spacing.sm) {
                        StatisticChip(label: "Providers", value: "\(model.summary.providerCount)")
                        StatisticChip(label: "Live", value: "\(model.summary.channelCount)")
                        StatisticChip(label: "Movies", value: "\(model.summary.movieCount)")
                        StatisticChip(label: "Series", value: "\(model.summary.seriesCount)")
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Import provider")
                            .font(.headline)

                        TextField("Provider name", text: $providerName)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexProviderNameInput()

                        TextField("M3U URL", text: $playlistURL)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexURLFieldInput()

                        Text("Or paste the playlist below. If both are filled, pasted content wins.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.muted)

                        TextEditor(text: $playlistText)
                            .frame(minHeight: 180)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task {
                                await model.importPlaylist(
                                    name: providerName,
                                    urlString: playlistURL,
                                    pastedContent: playlistText
                                )
                            }
                        } label: {
                            HStack {
                                if model.isImporting {
                                    ProgressView()
                                        .tint(AppTheme.Colors.onSurface)
                                }
                                Text(importButtonLabel)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                        .disabled(model.isImporting || providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let progress = model.importPipelineProgress, model.isImporting {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("\(progress.stage.rawValue): \(progress.parsedCount) parsed · \(progress.classifiedLive) live, \(progress.classifiedMovie) movies, \(progress.classifiedSeries) series · \(progress.dedupSkipped) dedup skipped · \(progress.classifiedUncertain) uncertain")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.muted)
                                if let eta = progress.estimatedSecondsRemaining, eta > 0 {
                                    Text("~\(eta)s remaining")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.Colors.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let importStatusMessage = model.importStatusMessage {
                            Text(importStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.muted)
                        }
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Import Xtream Codes")
                            .font(.headline)

                        TextField("Provider name", text: $providerName)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexProviderNameInput()

                        TextField("Server URL (e.g. http://server:port)", text: $xtreamServerURL)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexURLFieldInput()

                        TextField("Username", text: $xtreamUsername)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexProviderNameInput()

                        SecureField("Password", text: $xtreamPassword)
                            .padding(AppTheme.Spacing.sm)
                            .background(AppTheme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .youflexSecretFieldInput()

                        Button {
                            Task {
                                await model.importXtreamProvider(
                                    name: providerName,
                                    serverURLString: xtreamServerURL,
                                    username: xtreamUsername,
                                    password: xtreamPassword
                                )
                            }
                        } label: {
                            HStack {
                                if model.isImporting {
                                    ProgressView()
                                        .tint(AppTheme.Colors.onSurface)
                                }
                                Text(model.isImporting ? "Importing..." : "Import Xtream")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.accent)
                        .disabled(
                            model.isImporting ||
                            providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            xtreamServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            xtreamPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Providers")
                            .font(.headline)

                        if model.providers.isEmpty {
                            Text("No providers imported yet.")
                                .foregroundStyle(AppTheme.Colors.muted)
                        } else {
                            ForEach(model.providers) { provider in
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(provider.name)
                                        .foregroundStyle(AppTheme.Colors.onSurface)
                                    Text(provider.m3uUrl ?? provider.xtreamServer ?? "Inline M3U playlist")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.muted)
                                }
                                if provider.id != model.providers.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }
}
