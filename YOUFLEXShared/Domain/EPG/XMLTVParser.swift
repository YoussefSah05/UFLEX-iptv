import Foundation

/// Parses XMLTV EPG files into channel and programme records.
/// Pure domain; no SwiftUI/UIKit.
struct XMLTVParser {
    fileprivate static let formatters: [DateFormatter] = {
        let formats = [
            "yyyyMMddHHmmss xx",
            "yyyyMMddHHmmss Z",
            "yyyyMMddHHmmss"
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }
    }()

    func parse(data: Data) throws -> XMLTVResult {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XMLTVParseError.parseFailed(parser.parserError?.localizedDescription ?? "Unknown error")
        }
        return delegate.result
    }

    func parse(contentsOf url: URL) async throws -> XMLTVResult {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parse(data: data)
    }
}

struct XMLTVResult: Sendable {
    var channels: [XMLTVChannel] = []
    var programmes: [XMLTVProgramme] = []
}

struct XMLTVChannel: Sendable {
    var id: String
    var displayName: String
    var icon: String?
}

struct XMLTVProgramme: Sendable {
    var channelId: String
    var start: Date
    var stop: Date
    var title: String
    var description: String?
    var category: String?
}

enum XMLTVParseError: LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let msg):
            return "XMLTV parse failed: \(msg)"
        }
    }
}

// MARK: - Parser delegate

private final class ParserDelegate: NSObject, XMLParserDelegate {
    var result = XMLTVResult()

    private var currentChannel: (id: String, displayName: String, icon: String?)?
    private var currentProgramme: (channelId: String, start: Date?, stop: Date?, title: String?, description: String?, category: String?)?
    private var currentElement: String?
    private var currentValue = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""

        switch elementName {
        case "channel":
            if let id = attributeDict["id"] {
                currentChannel = (id: id, displayName: "", icon: nil)
            }
        case "icon":
            if var ch = currentChannel, let src = attributeDict["src"] {
                ch.icon = src
                currentChannel = ch
            }
        case "programme":
            let channelId = attributeDict["channel"] ?? ""
            let start = parseTime(attributeDict["start"])
            let stop = parseTime(attributeDict["stop"])
            currentProgramme = (channelId: channelId, start: start, stop: stop, title: nil, description: nil, category: nil)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "channel":
            if var ch = currentChannel {
                if ch.displayName.isEmpty { ch.displayName = ch.id }
                result.channels.append(XMLTVChannel(id: ch.id, displayName: ch.displayName, icon: ch.icon))
            }
            currentChannel = nil

        case "programme":
            if var prog = currentProgramme,
               let start = prog.start,
               let stop = prog.stop,
               !prog.channelId.isEmpty {
                if prog.title == nil || prog.title!.isEmpty {
                    prog.title = trimmed.isEmpty ? "Programme" : trimmed
                }
                result.programmes.append(XMLTVProgramme(
                    channelId: prog.channelId,
                    start: start,
                    stop: stop,
                    title: prog.title ?? "Programme",
                    description: prog.description,
                    category: prog.category
                ))
            }
            currentProgramme = nil

        case "display-name":
            if var ch = currentChannel, !trimmed.isEmpty {
                ch.displayName = trimmed
                currentChannel = ch
            } else if currentProgramme != nil, (currentProgramme!.title == nil || currentProgramme!.title!.isEmpty), !trimmed.isEmpty {
                currentProgramme?.title = trimmed
            }
        case "title":
            if currentProgramme != nil, !trimmed.isEmpty {
                currentProgramme?.title = trimmed
            }
        case "desc", "description":
            if currentProgramme != nil {
                currentProgramme?.description = trimmed.isEmpty ? nil : trimmed
            }
        case "category":
            if currentProgramme != nil {
                currentProgramme?.category = trimmed.isEmpty ? nil : trimmed
            }
        default:
            break
        }

        currentElement = nil
    }

    private func parseTime(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        for formatter in XMLTVParser.formatters {
            if let d = formatter.date(from: raw) {
                return d
            }
        }
        return nil
    }
}
