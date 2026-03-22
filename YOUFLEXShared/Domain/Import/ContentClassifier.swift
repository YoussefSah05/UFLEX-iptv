import Foundation

struct EpisodeIdentity: Equatable, Sendable {
    var seriesTitle: String
    var seasonNumber: Int
    var episodeNumber: Int
    var episodeTitle: String
}

enum ClassifiedContent: Equatable, Sendable {
    case channel
    case movie(year: Int?)
    case episode(EpisodeIdentity)
    indirect case uncertain(ClassifiedContent)
}

struct ClassificationResult: Sendable {
    let content: ClassifiedContent
    let confidence: Double
    let normalizedTitle: String
    let extractedYear: Int?

    var isUncertain: Bool { confidence < 0.7 }

    var effectiveContent: ClassifiedContent {
        if case let .uncertain(inner) = content {
            return inner
        }
        return content
    }
}

struct ContentClassifier: Sendable {
    private let movieCategoryKeywords = ["movie", "movies", "film", "films", "cinema", "vod"]
    private let vodPathPatterns = ["/movie/", "/vod/", "/films/", "/series/"]
    private let livePathPatterns = ["/live/", "/tv/", "/channels/"]
    private let codecTags = ["h264", "h265", "hevc", "x264", "x265", "avc", "aac"]
    private let qualityTags = ["hd", "fhd", "4k", "uhd", "hdr", "dolby"]

    func classify(_ entry: ParsedM3UEntry) -> ClassificationResult {
        let rawYear = detectYear(in: entry.title)
        let normalizedTitle = TitleNormalizer.normalizeForClassification(entry.title)

        if let identity = detectEpisodeIdentity(in: entry.title) {
            let confidence = scoreEpisode(entry: entry, identity: identity)
            return ClassificationResult(
                content: confidence >= 0.7 ? .episode(identity) : .uncertain(.episode(identity)),
                confidence: confidence,
                normalizedTitle: TitleNormalizer.canonicalSeriesTitle(from: identity.seriesTitle),
                extractedYear: rawYear
            )
        }

        let (movieScore, channelScore) = scoreMovieVsChannel(entry: entry, year: rawYear)
        if movieScore >= channelScore, movieScore >= 0.7 {
            return ClassificationResult(
                content: .movie(year: rawYear),
                confidence: movieScore,
                normalizedTitle: normalizedTitle,
                extractedYear: rawYear
            )
        }
        if channelScore >= 0.7 {
            return ClassificationResult(
                content: .channel,
                confidence: channelScore,
                normalizedTitle: normalizedTitle,
                extractedYear: rawYear
            )
        }
        let best = movieScore >= channelScore ? ClassifiedContent.movie(year: rawYear) : .channel
        return ClassificationResult(
            content: .uncertain(best),
            confidence: max(movieScore, channelScore),
            normalizedTitle: normalizedTitle,
            extractedYear: rawYear
        )
    }

    func detectYear(in title: String) -> Int? {
        let nsRange = NSRange(title.startIndex..., in: title)
        let regex = try? NSRegularExpression(pattern: #"(19|20)\d{2}"#)
        guard
            let match = regex?.firstMatch(in: title, options: [], range: nsRange),
            let range = Range(match.range, in: title)
        else {
            return nil
        }
        return Int(title[range])
    }

    private func scoreEpisode(entry: ParsedM3UEntry, identity: EpisodeIdentity) -> Double {
        var score = 0.7
        if identity.seriesTitle.count >= 2 { score += 0.1 }
        if identity.episodeNumber > 0, identity.seasonNumber > 0 { score += 0.1 }
        if entry.streamURL.pathExtension.lowercased().nonEmptyValue != nil { score += 0.05 }
        if entry.groupTitle?.localizedCaseInsensitiveContains("series") == true { score += 0.1 }
        return min(1.0, score)
    }

    private func scoreMovieVsChannel(entry: ParsedM3UEntry, year: Int?) -> (movie: Double, channel: Double) {
        var movieScore = 0.0
        var channelScore = 0.0

        if containsKeyword(entry.groupTitle, in: movieCategoryKeywords) { movieScore += 0.25 }
        if year != nil { movieScore += 0.15 }
        if let d = entry.duration, d > 3600 { movieScore += 0.2 }
        if let d = entry.duration, d > 1800 { movieScore += 0.1 }
        if entry.tvgID == nil, entry.tvgName == nil { movieScore += 0.15 }
        if let ext = entry.streamURL.pathExtension.lowercased().nonEmptyValue,
           ["mp4", "mkv", "avi", "mov", "m4v"].contains(ext) { movieScore += 0.15 }
        let path = entry.streamURL.path.lowercased()
        for p in vodPathPatterns where path.contains(p) { movieScore += 0.15; break }
        if entry.tvgID != nil || entry.tvgName != nil { channelScore += 0.2 }
        for p in livePathPatterns where path.contains(p) { channelScore += 0.25; break }
        if entry.groupTitle?.localizedCaseInsensitiveContains("live") == true { channelScore += 0.2 }
        if entry.groupTitle?.localizedCaseInsensitiveContains("sport") == true { channelScore += 0.15 }
        if entry.duration == nil || entry.duration == -1 { channelScore += 0.15 }

        return (min(1.0, movieScore), min(1.0, channelScore))
    }

    private func containsKeyword(_ value: String?, in keywords: [String]) -> Bool {
        guard let value else { return false }
        let lowercased = value.lowercased()
        return keywords.contains { lowercased.contains($0) }
    }

    private func detectEpisodeIdentity(in title: String) -> EpisodeIdentity? {
        let patterns = [
            #"(.*?)(?i)\bS(\d{1,2})E(\d{1,2})\b(?:\s*[-:]\s*(.*))?"#,
            #"(.*?)(?i)\b(\d{1,2})x(\d{1,2})\b(?:\s*[-:]\s*(.*))?"#,
            #"(.*?)(?i)\bseason\s+(\d+)\s+episode\s+(\d+)\b(?:\s*[-:]\s*(.*))?"#
        ]

        let nsRange = NSRange(title.startIndex..., in: title)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: title, options: [], range: nsRange) else { continue }

            let seriesTitle = capture(match, at: 1, in: title)
                .map(TitleNormalizer.canonicalSeriesTitle(from:))
                .flatMap { $0.isEmpty ? nil : $0 }
            let seasonNumber = capture(match, at: 2, in: title).flatMap(Int.init)
            let episodeNumber = capture(match, at: 3, in: title).flatMap(Int.init)
            let trailingEpisodeTitle = capture(match, at: 4, in: title)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

            guard let seriesTitle, let seasonNumber, let episodeNumber else { continue }

            let episodeTitle = trailingEpisodeTitle?.nonEmptyValue ?? title
            return EpisodeIdentity(
                seriesTitle: seriesTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeTitle: episodeTitle
            )
        }
        return nil
    }

    private func capture(_ match: NSTextCheckingResult, at index: Int, in title: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: title) else { return nil }
        let value = String(title[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension String {
    var nonEmptyValue: String? { isEmpty ? nil : self }
}
