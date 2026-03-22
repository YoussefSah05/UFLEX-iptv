import Foundation

enum AppPaths {
    static func baseDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YOUFLEX", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func databaseURL(fileManager: FileManager = .default) throws -> URL {
        try baseDirectory(fileManager: fileManager).appendingPathComponent("YOUFLEX.sqlite")
    }

    static func downloadsDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager)
            .appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func transcriptionDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager)
            .appendingPathComponent("Transcription", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func whisperModelsDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = try baseDirectory(fileManager: fileManager)
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func relativePath(for url: URL, fileManager: FileManager = .default) throws -> String {
        let base = try baseDirectory(fileManager: fileManager).standardizedFileURL.path
        let resolved = url.standardizedFileURL.path
        guard resolved.hasPrefix(base) else {
            return resolved
        }

        let start = resolved.index(resolved.startIndex, offsetBy: base.count)
        return String(resolved[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func resolvedURL(for storedPath: String, fileManager: FileManager = .default) throws -> URL {
        if storedPath.hasPrefix("/") {
            return URL(fileURLWithPath: storedPath)
        }
        return try baseDirectory(fileManager: fileManager).appendingPathComponent(storedPath)
    }
}
