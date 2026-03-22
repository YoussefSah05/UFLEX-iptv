import Foundation
import Security

/// Stores and retrieves credentials in the system Keychain.
/// Never writes to SQLite, UserDefaults, or files.
enum KeychainManager {
    private static let serviceName = "com.youflex.apple"

    enum Key: String, CaseIterable {
        case tmdbReadAccessToken = "tmdb.readAccessToken"
        case xtreamCredentials = "xtream.credentials."

        func fullKey(providerId: String? = nil) -> String {
            switch self {
            case .tmdbReadAccessToken:
                return rawValue
            case .xtreamCredentials:
                return rawValue + (providerId ?? "")
            }
        }
    }

    static func save(_ value: String, for key: Key, providerId: String? = nil) throws {
        let data = value.data(using: .utf8)!
        let fullKey = key.fullKey(providerId: providerId)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullKey,
        ]

        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        }

        if status != errSecSuccess {
            throw KeychainError.operationFailed(status: status)
        }
    }

    static func load(for key: Key, providerId: String? = nil) throws -> String? {
        let fullKey = key.fullKey(providerId: providerId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw KeychainError.operationFailed(status: status)
        }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(for key: Key, providerId: String? = nil) throws {
        let fullKey = key.fullKey(providerId: providerId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: fullKey,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.operationFailed(status: status)
        }
    }

    // MARK: - Convenience

    static func saveTMDBReadAccessToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try delete(for: .tmdbReadAccessToken)
        } else {
            try save(trimmed, for: .tmdbReadAccessToken)
        }
    }

    static func loadTMDBReadAccessToken() throws -> String {
        try load(for: .tmdbReadAccessToken) ?? ""
    }

    static func saveXtreamCredentials(username: String, password: String, providerId: String) throws {
        struct Payload: Codable {
            let username: String
            let password: String
        }
        let payload = Payload(username: username, password: password)
        let data = try JSONEncoder().encode(payload)
        try save(String(data: data, encoding: .utf8)!, for: .xtreamCredentials, providerId: providerId)
    }

    static func loadXtreamCredentials(providerId: String) throws -> (username: String, password: String)? {
        struct Payload: Codable {
            let username: String
            let password: String
        }
        guard let raw = try load(for: .xtreamCredentials, providerId: providerId),
              let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return (payload.username, payload.password)
    }

    static func deleteXtreamCredentials(providerId: String) throws {
        try delete(for: .xtreamCredentials, providerId: providerId)
    }
}

enum KeychainError: LocalizedError {
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            return "Keychain operation failed (status: \(status))"
        }
    }
}
