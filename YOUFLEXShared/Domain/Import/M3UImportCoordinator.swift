import CryptoKit
import Foundation
import GRDB

enum ProviderImportSource: Sendable {
    case remote(URL)
    case pasted(String)
}

enum ProviderImportError: LocalizedError, Sendable {
    case emptySource
    case emptyPlaylist

    var errorDescription: String? {
        switch self {
        case .emptySource:
            "Provide either an M3U URL or playlist text."
        case .emptyPlaylist:
            "The playlist did not contain any importable entries."
        }
    }
}

@MainActor
final class M3UImportCoordinator {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Runs the import pipeline. Progress is reported via the pipeline's progressStream.
    /// Pass an optional progressHandler to receive updates; it will be called on the MainActor.
    func importProvider(
        name: String,
        source: ProviderImportSource,
        progressHandler: (@MainActor (ImportPipelineProgress) -> Void)? = nil
    ) async throws -> ProviderImportSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProviderImportError.emptySource
        }

        let providerId = Self.stableIdentifier(prefix: "provider", seed: trimmedName.lowercased())
        let resumeFrom = try? database.fetchActiveImportJob(providerId: providerId)
        let jobId = resumeFrom?.id ?? Self.stableIdentifier(prefix: "import", seed: "\(providerId)|\(Date().timeIntervalSince1970)")

        let pipeline = ImportPipeline(database: database)

        let progressTask: Task<Void, Never>?
        if let progressHandler {
            let stream = await pipeline.progressStream
            progressTask = Task { @MainActor in
                for await progress in stream {
                    progressHandler(progress)
                }
            }
        } else {
            progressTask = nil
        }

        defer { progressTask?.cancel() }

        return try await pipeline.run(
            providerId: providerId,
            providerName: trimmedName,
            jobId: jobId,
            source: source,
            resumeFrom: resumeFrom
        )
    }

    nonisolated private static func stableIdentifier(prefix: String, seed: String) -> String {
        "\(prefix)-\(sha256(seed).prefix(16))"
    }

    nonisolated private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
