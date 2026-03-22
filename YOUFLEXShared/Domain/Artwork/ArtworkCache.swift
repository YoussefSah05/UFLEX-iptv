import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Downloads remote artwork, resizes with vImage, and stores on disk.
/// Returns relative paths for persistence in GRDB.
enum ArtworkCache {
    static let posterMaxDimension: CGFloat = 342
    static let backdropMaxDimension: CGFloat = 780

    static func artworkDirectory(fileManager: FileManager = .default) throws -> URL {
        let dir = try AppPaths.baseDirectory(fileManager: fileManager)
            .appendingPathComponent("Artwork", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downloads from URL, resizes if needed, saves to disk. Returns relative path or nil on failure.
    static func downloadAndCache(
        url: URL,
        contentType: String,
        contentId: String,
        variant: ArtworkVariant,
        maxDimension: CGFloat,
        session: URLSession = .shared
    ) async throws -> String? {
        let (data, _) = try await session.data(from: url)
        guard let image = decodeImage(data: data) else { return nil }
        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        let safeId = sanitizeForFilename(contentId)
        let filename = "\(contentType)-\(safeId)-\(variant.rawValue).jpg"
        let dir = try artworkDirectory()
        let fileURL = dir.appendingPathComponent(filename)
        guard saveAsJPEG(resized, to: fileURL) else { return nil }
        return try AppPaths.relativePath(for: fileURL)
    }

    static func downloadAndCachePoster(
        url: URL,
        contentType: String,
        contentId: String,
        session: URLSession = .shared
    ) async throws -> String? {
        try await downloadAndCache(
            url: url,
            contentType: contentType,
            contentId: contentId,
            variant: .poster,
            maxDimension: posterMaxDimension,
            session: session
        )
    }

    static func downloadAndCacheBackdrop(
        url: URL,
        contentType: String,
        contentId: String,
        session: URLSession = .shared
    ) async throws -> String? {
        try await downloadAndCache(
            url: url,
            contentType: contentType,
            contentId: contentId,
            variant: .backdrop,
            maxDimension: backdropMaxDimension,
            session: session
        )
    }

    private static func sanitizeForFilename(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce("") { $0 + String($1) }
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
    }

    private static func decodeImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cgImage
    }

    private static func resizeIfNeeded(_ cgImage: CGImage, maxDimension: CGFloat) -> CGImage {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > maxDimension || h > maxDimension else {
            return cgImage
        }
        let scale = min(maxDimension / w, maxDimension / h)
        let newW = Int(w * scale)
        let newH = Int(h * scale)
        guard newW > 0, newH > 0 else { return cgImage }
        return resizeWithVImage(cgImage, targetWidth: newW, targetHeight: newH) ?? cgImage
    }

    private static func resizeWithVImage(_ source: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        defer { format.colorSpace?.release() }

        var sourceBuffer = vImage_Buffer()
        defer {
            if sourceBuffer.data != nil {
                sourceBuffer.data?.deallocate()
            }
        }
        var err = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, source, vImage_Flags(kvImageNoFlags))
        guard err == kvImageNoError else { return resizeWithCGContext(source, targetWidth: targetWidth, targetHeight: targetHeight) }

        let bytesPerPixel = 4
        let destBytesPerRow = targetWidth * bytesPerPixel
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: targetHeight * destBytesPerRow)
        defer { destData.deallocate() }
        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: destBytesPerRow
        )

        err = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard err == kvImageNoError else { return resizeWithCGContext(source, targetWidth: targetWidth, targetHeight: targetHeight) }

        var createErr = vImage_Error(kvImageNoError)
        guard let result = vImageCreateCGImageFromBuffer(
            &destBuffer,
            &format,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags),
            &createErr
        )?.takeRetainedValue(), createErr == kvImageNoError else {
            return resizeWithCGContext(source, targetWidth: targetWidth, targetHeight: targetHeight)
        }
        return result
    }

    private static func resizeWithCGContext(_ source: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private static func saveAsJPEG(_ cgImage: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}

enum ArtworkVariant: String {
    case poster
    case backdrop
}
