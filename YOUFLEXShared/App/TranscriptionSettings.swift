import Foundation

enum TranscriptionSettings {
    private static let modelKey = "youflex.transcription.preferredModel"

    static func loadPreferredModel(userDefaults: UserDefaults = .standard) -> String {
        userDefaults.string(forKey: modelKey) ?? ""
    }

    static func savePreferredModel(_ model: String, userDefaults: UserDefaults = .standard) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: modelKey)
        } else {
            userDefaults.set(trimmed, forKey: modelKey)
        }
    }
}
