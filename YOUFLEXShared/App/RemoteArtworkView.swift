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

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
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
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: urlString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = resolvedURL else {
            image = nil
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
        guard let urlString, let url = URL(string: urlString) else {
            return nil
        }
        return url
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
