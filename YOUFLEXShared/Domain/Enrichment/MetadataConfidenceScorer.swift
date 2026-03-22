import Foundation

enum MetadataConfidenceScorer {
    static func movieScore(
        importedTitle: String,
        importedYear: Int?,
        candidateTitle: String,
        candidateYear: Int?
    ) -> Double {
        score(
            importedTitle: importedTitle,
            importedYear: importedYear,
            candidateTitle: candidateTitle,
            candidateYear: candidateYear
        )
    }

    static func seriesScore(
        importedTitle: String,
        candidateTitle: String,
        candidateYear: Int?
    ) -> Double {
        score(
            importedTitle: importedTitle,
            importedYear: nil,
            candidateTitle: candidateTitle,
            candidateYear: candidateYear
        )
    }

    private static func score(
        importedTitle: String,
        importedYear: Int?,
        candidateTitle: String,
        candidateYear: Int?
    ) -> Double {
        let normalizedImported = normalizedTitle(importedTitle)
        let normalizedCandidate = normalizedTitle(candidateTitle)

        guard !normalizedImported.isEmpty, !normalizedCandidate.isEmpty else {
            return 0
        }

        let titleScore: Double
        if normalizedImported == normalizedCandidate {
            titleScore = 0.78
        } else {
            let importedTokens = Set(normalizedImported.split(separator: " ").map(String.init))
            let candidateTokens = Set(normalizedCandidate.split(separator: " ").map(String.init))
            let union = importedTokens.union(candidateTokens)
            let overlap = union.isEmpty ? 0 : Double(importedTokens.intersection(candidateTokens).count) / Double(union.count)
            titleScore = 0.28 + (overlap * 0.5)
        }

        let yearScore: Double
        if let importedYear, let candidateYear {
            switch abs(importedYear - candidateYear) {
            case 0:
                yearScore = 0.22
            case 1:
                yearScore = 0.12
            default:
                yearScore = -0.08
            }
        } else {
            yearScore = 0
        }

        return min(max(titleScore + yearScore, 0), 1)
    }

    static func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
