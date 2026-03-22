import Foundation

/// Fetches channel logo URLs from iptv-org/api. Use when M3U tvg-logo is absent.
enum IPTVOrgLogoClient {
    private static let shared = Client()

    /// Returns logo URL for channel id (tvg-id or tvg-name). Fetches and caches logos on first use.
    static func logoURL(for channelId: String, session: URLSession = .shared) async -> String? {
        await shared.logoURL(for: channelId, session: session)
    }

    private actor Client {
        private let logosURL = URL(string: "https://iptv-org.github.io/api/logos.json")!
        private var cache: [String: String]?

        func logoURL(for channelId: String, session: URLSession) async -> String? {
            guard !channelId.isEmpty else { return nil }
            let map = await loadLogos(session: session)
            let normalized = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
            return map[normalized] ?? map[normalized.lowercased()]
        }

        private func loadLogos(session: URLSession) async -> [String: String] {
            if let c = cache { return c }

            guard let (data, _) = try? await session.data(from: logosURL),
                  let items = try? JSONDecoder().decode([LogoItem].self, from: data) else {
                cache = [:]
                return [:]
            }

            var map: [String: String] = [:]
            for item in items {
                guard !item.channel.isEmpty, let url = item.url, !url.isEmpty else { continue }
                if map[item.channel] == nil {
                    map[item.channel] = url
                }
            }
            cache = map
            return map
        }
    }

    private struct LogoItem: Decodable {
        let channel: String
        let url: String?
    }
}
