import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Metadata for a WhisperKit-compatible model.
struct WhisperKitModelInfo: Sendable {
    let id: String
    let displayName: String
    let sizeBytes: Int64
    let recommendedFor: DeviceTier

    static let tiny = WhisperKitModelInfo(
        id: "openai_whisper_tiny",
        displayName: "Tiny",
        sizeBytes: 75 * 1_024 * 1_024,
        recommendedFor: .legacy
    )
    static let base = WhisperKitModelInfo(
        id: "openai_whisper_base",
        displayName: "Base",
        sizeBytes: 142 * 1_024 * 1_024,
        recommendedFor: .legacy
    )
    static let small = WhisperKitModelInfo(
        id: "openai_whisper_small",
        displayName: "Small",
        sizeBytes: 466 * 1_024 * 1_024,
        recommendedFor: .iphoneA17
    )
    static let medium = WhisperKitModelInfo(
        id: "openai_whisper_medium",
        displayName: "Medium",
        sizeBytes: 1_500 * 1_024 * 1_024,
        recommendedFor: .ipad
    )
    static let largeV3 = WhisperKitModelInfo(
        id: "openai_whisper_large_v3",
        displayName: "Large V3",
        sizeBytes: 3_000 * 1_024 * 1_024,
        recommendedFor: .mac
    )

    static let all: [WhisperKitModelInfo] = [tiny, base, small, medium, largeV3]

    /// Recommended model ID for the current device.
    static var recommendedModelIdForCurrentDevice: String {
        let tier = DeviceTier.current
        return all.first { $0.recommendedFor == tier }?.id ?? small.id
    }

    var sizeFormatted: String {
        let mb = Double(sizeBytes) / (1_024 * 1_024)
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

enum DeviceTier: String, Sendable {
    case mac = "mac"
    case ipad = "ipad"
    case iphoneA17 = "iphone_a17"
    case legacy = "legacy"

    static var current: DeviceTier {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        #if targetEnvironment(simulator)
        return .ipad
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return .mac
        }
        let isMSeries = Self.isAppleSilicon
        if Self.isIPad {
            return isMSeries ? .ipad : .legacy
        }
        if Self.isA17OrNewer {
            return .iphoneA17
        }
        return .legacy
        #endif
        #else
        return .legacy
        #endif
    }

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    private static var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    private static var isA17OrNewer: Bool {
        #if os(iOS) && !targetEnvironment(simulator)
        let name = ProcessInfo.processInfo.machine
        return name.contains("iPhone18") || name.contains("iPhone19") || name.contains("iPhone2")
        #else
        return false
        #endif
    }
}

/// Download state for a model.
enum WhisperKitModelDownloadState: Sendable {
    case idle
    case downloading(bytesDownloaded: Int64, bytesTotal: Int64?, progress: Double?, estimatedSecondsRemaining: Int?)
    case verifying
    case ready
    case failed(String)
}

/// Manages WhisperKit model lifecycle: which models exist, which are cached,
/// device-specific recommendation, download with progress, and model switching.
@MainActor
@Observable
final class WhisperKitModelManager {
    var availableModels: [WhisperKitModelInfo] { WhisperKitModelInfo.all }
    var activeModelId: String?
    var downloadStates: [String: WhisperKitModelDownloadState] = [:]
    var lastError: String?

    private let modelsDirectory: URL
    private var loadTask: Task<(), Never>?

    init() {
        modelsDirectory = (try? AppPaths.whisperModelsDirectory()) ?? FileManager.default.temporaryDirectory
    }

    /// Recommended model for the current device based on chip and memory.
    var recommendedModelId: String {
        WhisperKitModelInfo.recommendedModelIdForCurrentDevice
    }

    /// Whether the model is already downloaded and cached.
    func isModelCached(_ modelId: String) -> Bool {
        let dir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    /// Disk size of a cached model in bytes, or nil if not cached.
    func cachedModelSizeBytes(_ modelId: String) -> Int64? {
        let dir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    /// Ensure the model is downloaded and ready. Updates downloadStates with progress.
    func ensureModelDownloaded(_ modelId: String) async {
        if isModelCached(modelId) {
            downloadStates[modelId] = .ready
            return
        }

        downloadStates[modelId] = .downloading(
            bytesDownloaded: 0,
            bytesTotal: WhisperKitModelInfo.all.first { $0.id == modelId }?.sizeBytes,
            progress: nil,
            estimatedSecondsRemaining: nil
        )
        lastError = nil

        do {
            #if canImport(WhisperKit)
            let config = WhisperKitConfig(
                model: modelId,
                downloadBase: modelsDirectory,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: true
            )
            downloadStates[modelId] = .verifying
            _ = try await WhisperKit(config)
            downloadStates[modelId] = .ready
            #else
            downloadStates[modelId] = .failed("WhisperKit is not available on this platform.")
            #endif
        } catch {
            downloadStates[modelId] = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    /// Cancel any in-flight download. WhisperKit does not expose cancellation;
    /// this clears our state. The underlying download may continue.
    func cancelDownload(_ modelId: String) {
        downloadStates[modelId] = .idle
    }

    /// Unload the current model to free memory. Call before switching models.
    func unloadActiveModel() {
        loadTask?.cancel()
        loadTask = nil
        activeModelId = nil
    }

    /// Set the active model. Unloads the previous model and loads the new one.
    func setActiveModel(_ modelId: String?) {
        unloadActiveModel()
        activeModelId = modelId
    }
}

#if os(iOS)
import UIKit
#endif
