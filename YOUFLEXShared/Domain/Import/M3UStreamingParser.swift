import Foundation

/// Streams parsed M3U entries line-by-line from a URL. Memory does not grow with playlist size.
/// Uses URLSession bytes for true streaming HTTP.
struct M3UStreamingParser: Sendable {
    private let lineParser = M3UParser()

    /// Yields parsed entries as they become available from the stream.
    /// - Parameters:
    ///   - url: The M3U playlist URL to fetch and parse.
    ///   - session: URLSession for the request (default: shared).
    /// - Returns: AsyncThrowingStream of ParsedM3UEntry.
    func parse(
        from url: URL,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<ParsedM3UEntry, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let baseURL = url.deletingLastPathComponent()
                    var buffer = ""
                    var pendingEXTINF: (duration: Int?, title: String, attributes: [String: String])?
                    var lineCount = 0

                    let (bytes, response) = try await session.bytes(from: url)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }

                    for try await byte in bytes {
                        let character = Character(Unicode.Scalar(byte))
                        if character == "\n" || character == "\r" {
                            let line = buffer
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "\r", with: "")
                            buffer = ""
                            lineCount += 1

                            if line.isEmpty {
                                continue
                            }

                            if line.hasPrefix("#EXTINF:") {
                                let extinf = String(line.dropFirst("#EXTINF:".count))
                                pendingEXTINF = parseEXTINF(extinf)
                                continue
                            }

                            if line.hasPrefix("#") {
                                continue
                            }

                            if let extinf = pendingEXTINF {
                                if let streamURL = resolveURL(line, baseURL: baseURL) {
                                    let normalizedTitle = TitleNormalizer.normalizeDisplayTitle(extinf.title)
                                    let entry = ParsedM3UEntry(
                                        duration: extinf.duration,
                                        rawTitle: extinf.title,
                                        title: normalizedTitle,
                                        streamURL: streamURL,
                                        attributes: extinf.attributes
                                    )
                                    continuation.yield(entry)
                                }
                                pendingEXTINF = nil
                            }
                        } else {
                            buffer.append(character)
                        }
                    }

                    if !buffer.isEmpty {
                        let line = buffer
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\r", with: "")
                        if !line.isEmpty, line.hasPrefix("#EXTINF:") {
                            let extinf = String(line.dropFirst("#EXTINF:".count))
                            _ = parseEXTINF(extinf)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Yields parsed entries from pasted string content (non-streaming).
    func parse(
        from string: String,
        baseURL: URL? = nil
    ) -> AsyncThrowingStream<ParsedM3UEntry, Error> {
        AsyncThrowingStream { continuation in
            let entries = lineParser.parse(string, baseURL: baseURL)
            for entry in entries {
                continuation.yield(entry)
            }
            continuation.finish()
        }
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
