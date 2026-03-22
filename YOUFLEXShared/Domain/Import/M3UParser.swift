import Foundation

struct ParsedM3UEntry: Equatable, Sendable {
    var duration: Int?
    var rawTitle: String
    var title: String
    var streamURL: URL
    var attributes: [String: String]

    var groupTitle: String? { attributes["group-title"] }
    var tvgID: String? { attributes["tvg-id"] }
    var tvgName: String? { attributes["tvg-name"] }
    var logoURL: String? { attributes["tvg-logo"] ?? attributes["group-logo"] ?? attributes["logo"] }
}

struct M3UParser {
    func parse(_ content: String, baseURL: URL? = nil) -> [ParsedM3UEntry] {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var entries: [ParsedM3UEntry] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("#EXTINF:") else {
                index += 1
                continue
            }

            let extinf = String(line.dropFirst("#EXTINF:".count))
            let parsed = parseEXTINF(extinf)

            var streamURL: URL?
            var candidateIndex = index + 1
            while candidateIndex < lines.count {
                let candidate = lines[candidateIndex]
                if candidate.isEmpty {
                    candidateIndex += 1
                    continue
                }
                if candidate.hasPrefix("#") {
                    if candidate.hasPrefix("#EXTINF:") {
                        break
                    }
                    candidateIndex += 1
                    continue
                }

                streamURL = resolveURL(candidate, baseURL: baseURL)
                break
            }

            if let streamURL {
                let normalizedTitle = TitleNormalizer.normalizeDisplayTitle(parsed.title)
                entries.append(
                    ParsedM3UEntry(
                        duration: parsed.duration,
                        rawTitle: parsed.title,
                        title: normalizedTitle,
                        streamURL: streamURL,
                        attributes: parsed.attributes
                    )
                )
            }

            if streamURL == nil {
                index = candidateIndex
            } else {
                index = candidateIndex + 1
            }
        }

        return entries
    }

    private func resolveURL(_ rawValue: String, baseURL: URL?) -> URL? {
        if let absoluteURL = URL(string: rawValue), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }

    private func parseEXTINF(_ line: String) -> (duration: Int?, title: String, attributes: [String: String]) {
        let components = splitMetadataAndTitle(line)
        let metadata = components.metadata
        let title = components.title

        let tokens = metadata.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let duration = tokens.first.flatMap { Int($0) }
        let attributeString = tokens.count > 1 ? String(tokens[1]) : ""

        return (
            duration: duration,
            title: title,
            attributes: parseAttributes(attributeString)
        )
    }

    private func splitMetadataAndTitle(_ line: String) -> (metadata: String, title: String) {
        var inQuotes = false
        var splitIndex: String.Index?

        for index in line.indices {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                splitIndex = index
                break
            }
        }

        guard let splitIndex else {
            return (line, line)
        }

        let metadata = String(line[..<splitIndex])
        let title = String(line[line.index(after: splitIndex)...])
        return (metadata, title)
    }

    private func parseAttributes(_ value: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let characters = Array(value)
        var index = 0

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count else {
                break
            }

            let keyStart = index
            while index < characters.count, !characters[index].isWhitespace, characters[index] != "=" {
                index += 1
            }
            guard index < characters.count, characters[index] == "=" else {
                while index < characters.count, !characters[index].isWhitespace {
                    index += 1
                }
                continue
            }

            let key = String(characters[keyStart..<index]).lowercased()
            index += 1

            var parsedValue = ""
            if index < characters.count, characters[index] == "\"" {
                index += 1
                while index < characters.count, characters[index] != "\"" {
                    parsedValue.append(characters[index])
                    index += 1
                }
                if index < characters.count, characters[index] == "\"" {
                    index += 1
                }
            } else {
                while index < characters.count, !characters[index].isWhitespace {
                    parsedValue.append(characters[index])
                    index += 1
                }
            }

            if !key.isEmpty {
                attributes[key] = parsedValue
            }
        }

        return attributes
    }
}
