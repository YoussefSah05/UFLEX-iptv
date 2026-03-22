import Nuke
import SwiftUI

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#else
import AppKit
private typealias PlatformImage = NSImage
#endif

struct RemoteArtworkView: View {
    let urlString: String?
    let placeholderSystemImage: String
    let size: CGSize
    var cornerRadius: CGFloat = AppTheme.Corner.card
    /// Fallback text for initials placeholder when no image (e.g. movie/series title).
    var placeholderTitle: String?

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: urlString) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let title = placeholderTitle, !title.isEmpty, let initials = Self.initials(from: title) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surfaceElevated)
            Text(initials)
                .font(.system(size: min(size.width, size.height) * 0.35, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.muted)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surfaceElevated)
                Image(systemName: placeholderSystemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.muted)
            }
        }
    }

    private func loadImage() async {
        guard let url = resolvedURL else {
            image = nil
            return
        }

        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let img = PlatformImage(data: data) {
                image = img
            } else {
                image = nil
            }
            return
        }

        do {
            let task = ImagePipeline.shared.imageTask(with: url)
            image = try await task.image
        } catch {
            image = nil
        }
    }

    private var resolvedURL: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        if urlString.lowercased().hasPrefix("http://") || urlString.lowercased().hasPrefix("https://") {
            return URL(string: urlString)
        }
        return try? AppPaths.resolvedURL(for: urlString)
    }

    private static func initials(from title: String) -> String? {
        let words = title.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        if words.count == 1, let first = words[0].first {
            return String(first).uppercased()
        }
        let first = words[0].first.map(String.init) ?? ""
        let last = words.count > 1 ? (words.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
