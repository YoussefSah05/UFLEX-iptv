import Foundation

enum TMDBSettings {
    static func loadReadAccessToken(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> String {
        if let stored = (try? KeychainManager.loadTMDBReadAccessToken()), !stored.isEmpty {
            return stored
        }
        if let environmentValue = processInfo.environment["TMDB_API_READ_ACCESS_TOKEN"]?.trimmedNonEmptyValue {
            return environmentValue
        }
        if let bundledValue = bundle.object(forInfoDictionaryKey: "TMDBReadAccessToken") as? String,
           let trimmed = bundledValue.trimmedNonEmptyValue {
            return trimmed
        }
        return ""
    }

    static func saveReadAccessToken(_ token: String) {
        let trimmed = token.trimmedNonEmptyValue ?? ""
        try? KeychainManager.saveTMDBReadAccessToken(trimmed)
    }
}

private extension String {
    var trimmedNonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
