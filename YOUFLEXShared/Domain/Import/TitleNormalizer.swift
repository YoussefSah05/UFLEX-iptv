import Foundation

enum TitleNormalizer {
    /// Normalizes title for classification and TMDB matching. Strips quality tags, codecs, and garbage.
    static func normalizeForClassification(_ rawTitle: String) -> String {
        var t = rawTitle
        let patterns = [
            #"(?i)\b(HD|FHD|UHD|4K|2K|8K|HDR|HDR10|Dolby Vision|DV)\b"#,
            #"(?i)\b(H\.?264|H\.?265|HEVC|AVC|X264|X265|AAC|AC3|DTS)\b"#,
            #"(?i)\b(720p|1080p|2160p|4K)\b"#,
            #"\[.*?\]"#,
            #"\(.*?\)"#,
            #"\{.*?\}"#,
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.isEmpty ? rawTitle : t
    }

    static func normalizeDisplayTitle(_ rawTitle: String) -> String {
        let metadataPatterns = [
            #"(?:^|\s)(?:tvg-id|tvg-name|tvg-logo|group-title|group-logo|logo|catchup|catchup-source|catchup-days|provider-type)="[^"]*""#,
            #"(?:^|\s)(?:tvg-id|tvg-name|tvg-logo|group-title|group-logo|logo|catchup|catchup-source|catchup-days|provider-type)=[^\s]+"#
        ]

        var title = rawTitle
        for pattern in metadataPatterns {
            title = title.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: " ,", with: ",")
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if title.isEmpty {
            return rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return title
    }

    static func canonicalSeriesTitle(from title: String) -> String {
        let patterns = [
            #"(?i)\bS\d{1,2}E\d{1,2}\b"#,
            #"(?i)\b\d{1,2}x\d{1,2}\b"#,
            #"(?i)\bseason\s+\d+\s+episode\s+\d+\b"#
        ]

        var output = title
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        output = output.replacingOccurrences(of: "[-_:]+", with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
