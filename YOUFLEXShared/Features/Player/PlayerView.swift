import AVKit
import SwiftUI

struct PlayerView: View {
    let model: AppModel
    let presentation: PlaybackPresentation
    @State private var coordinator = AVPlayerCoordinator()
    @State private var transcriptSegments: [TranscriptSegmentRecord] = []
    @State private var isGeneratingTranscript = false
    @State private var isStartingDownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            PlayerControlsContainer(
                coordinator: coordinator,
                presentation: presentation,
                activeTranscriptText: overlayTranscriptText
            ) {
                VideoPlayer(player: coordinator.player)
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            PanelCard {
                Text(presentation.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.onSurface)

                if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.muted)
                }

                HStack(spacing: AppTheme.Spacing.md) {
                    StatisticChip(label: "State", value: statusText)
                    StatisticChip(label: "Elapsed", value: coordinator.currentTimeText)
                    StatisticChip(label: "Duration", value: coordinator.durationText)
                    if presentation.kind != .live {
                        StatisticChip(label: "Transcript", value: transcriptStateLabel)
                    }
                }

                if let synopsis = presentation.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.body)
                        .foregroundStyle(AppTheme.Colors.muted)
                }

                if presentation.kind != .live {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Button {
                            isGeneratingTranscript = true
                            Task {
                                await model.generateTranscript(for: presentation)
                                transcriptSegments = model.transcriptSegments(for: presentation)
                                isGeneratingTranscript = false
                            }
                        } label: {
                            HStack {
                                if isGeneratingTranscript {
                                    ProgressView()
                                }
                                Text(isGeneratingTranscript ? "Transcribing..." : transcriptActionTitle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratingTranscript)

                        Button {
                            isStartingDownload = true
                            Task {
                                await model.startDownload(for: presentation)
                                isStartingDownload = false
                            }
                        } label: {
                            HStack {
                                if isStartingDownload {
                                    ProgressView()
                                }
                                Text(downloadActionTitle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isStartingDownload)
                    }
                }
            }

            if presentation.kind != .live {
                PanelCard {
                    Text("Transcript")
                        .font(.headline)
                    if transcriptSegments.isEmpty {
                        Text(transcriptEmptyMessage)
                            .foregroundStyle(AppTheme.Colors.muted)
                    } else {
                        ForEach(Array(transcriptSegments.prefix(6))) { segment in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text(timecode(for: segment))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(AppTheme.Colors.muted)
                                Text(segment.text)
                                    .foregroundStyle(AppTheme.Colors.onSurface)
                            }
                            if segment.id != transcriptSegments.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }

                    if let transcriptionStatusMessage = model.transcriptionStatusMessage {
                        Text(transcriptionStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.muted)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle(presentation.title)
        .youflexInlineTitleMode()
        .task(id: presentation.id) {
            transcriptSegments = model.transcriptSegments(for: presentation)
            var resolvedPresentation = presentation
            resolvedPresentation.streamURL = model.resolvedPlaybackURL(for: presentation)
            coordinator.load(
                resolvedPresentation,
                resumePositionMs: model.resumePosition(for: presentation)
            )
        }
        .task(id: "autosave-\(presentation.id)") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                persistProgress()
            }
        }
        .onDisappear {
            persistProgress()
            coordinator.stop()
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case .ready:
            return coordinator.isPlaying ? "Playing" : "Ready"
        case let .failed(message):
            return message
        }
    }

    private var activeTranscriptText: String? {
        transcriptSegments.first(where: { segment in
            coordinator.currentPositionMs >= segment.startMs && coordinator.currentPositionMs <= segment.endMs
        })?.text
    }

    /// VOD: timed transcript segments. Live: on-device speech recognition.
    private var overlayTranscriptText: String? {
        if presentation.kind == .live {
            let t = coordinator.liveCaptionText
            return t.isEmpty ? nil : t
        }
        return activeTranscriptText
    }

    private var transcriptStateLabel: String {
        switch model.transcriptStatus(for: presentation) {
        case "ready":
            return "Ready"
        case "in_progress":
            return "Working"
        case "failed":
            return "Failed"
        default:
            return "Missing"
        }
    }

    private var transcriptActionTitle: String {
        transcriptSegments.isEmpty ? "Generate Transcript" : "Refresh Transcript"
    }

    private var downloadActionTitle: String {
        if let download = model.downloadRecord(for: presentation), download.status == "completed" {
            return "Downloaded"
        }
        return "Download"
    }

    private var transcriptEmptyMessage: String {
        switch model.transcriptStatus(for: presentation) {
        case "failed":
            return "Transcript generation failed for this item. Try again after checking the local model and media source."
        case "in_progress":
            return "Transcript generation is running."
        default:
            return "No local transcript exists yet for this item."
        }
    }

    private func timecode(for segment: TranscriptSegmentRecord) -> String {
        "\(format(milliseconds: segment.startMs)) - \(format(milliseconds: segment.endMs))"
    }

    private func format(milliseconds: Int64) -> String {
        let totalSeconds = max(Int(milliseconds / 1_000), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func persistProgress() {
        guard presentation.kind != .live else { return }
        let durationMs = coordinator.currentDurationMs
        guard durationMs > 0 else { return }
        model.recordProgress(
            for: presentation,
            positionMs: coordinator.currentPositionMs,
            durationMs: durationMs
        )
    }
}
