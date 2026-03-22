import AVKit
import SwiftUI

/// Platform-specific player control overlays and layout.
/// Selected via compile-time and runtime checks.
struct PlayerControlsContainer<Content: View>: View {
    let coordinator: AVPlayerCoordinator
    let presentation: PlaybackPresentation
    let activeTranscriptText: String?
    let content: () -> Content

    var body: some View {
        #if os(macOS)
        MacPlayerControls(
            coordinator: coordinator,
            presentation: presentation,
            activeTranscriptText: activeTranscriptText,
            content: content
        )
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadPlayerControls(
                coordinator: coordinator,
                presentation: presentation,
                activeTranscriptText: activeTranscriptText,
                content: content
            )
        } else {
            iPhonePlayerControls(
                coordinator: coordinator,
                presentation: presentation,
                activeTranscriptText: activeTranscriptText,
                content: content
            )
        }
        #endif
    }
}

// MARK: - iPhone

#if os(iOS)
private struct iPhonePlayerControls<Content: View>: View {
    let coordinator: AVPlayerCoordinator
    let presentation: PlaybackPresentation
    let activeTranscriptText: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                Text(presentation.kind.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(AppTheme.Spacing.sm)
            }
            .overlay(alignment: .bottom) {
                if let activeTranscriptText {
                    Text(activeTranscriptText)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.75))
                        .padding(AppTheme.Spacing.sm)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
    }
}
#endif

// MARK: - iPad

#if os(iOS)
private struct iPadPlayerControls<Content: View>: View {
    let coordinator: AVPlayerCoordinator
    let presentation: PlaybackPresentation
    let activeTranscriptText: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                Text(presentation.kind.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(AppTheme.Spacing.md)
            }
            .overlay(alignment: .bottom) {
                if let activeTranscriptText {
                    Text(activeTranscriptText)
                        .font(.headline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
                        .padding(AppTheme.Spacing.md)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
    }
}
#endif

// MARK: - Mac

#if os(macOS)
private struct MacPlayerControls<Content: View>: View {
    let coordinator: AVPlayerCoordinator
    let presentation: PlaybackPresentation
    let activeTranscriptText: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                Text(presentation.kind.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(AppTheme.Spacing.md)
            }
            .overlay(alignment: .bottom) {
                if let activeTranscriptText {
                    Text(activeTranscriptText)
                        .font(.headline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
                        .padding(AppTheme.Spacing.md)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
    }
}
#endif
