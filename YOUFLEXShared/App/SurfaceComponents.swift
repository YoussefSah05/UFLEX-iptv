import SwiftUI

struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            content
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.card, style: .continuous))
    }
}

struct StatisticChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.Colors.muted)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.onSurface)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.button, style: .continuous))
    }
}

struct ProgressPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.onSurface)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.surfaceElevated)
            .clipShape(Capsule())
    }
}

struct EmptyLibraryState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .foregroundStyle(AppTheme.Colors.onBackground, AppTheme.Colors.muted)
    }
}

extension View {
    @ViewBuilder
    func youflexInlineTitleMode() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func youflexProviderNameInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func youflexURLFieldInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.URL)
            .keyboardType(.URL)
        #else
        self
        #endif
    }

    @ViewBuilder
    func youflexSecretFieldInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
        #else
        self
        #endif
    }
}
