import Foundation

/// Builds WebVTT subtitle content from transcript segments.
/// Cue rules: max 2 lines per cue, 42 chars per line, 7 seconds per cue.
/// Breaks at sentence boundaries where possible.
enum VTTBuilder {
    static let maxCharsPerLine = 42
    static let maxLinesPerCue = 2
    static let maxCueDurationMs: Int64 = 7_000

    static func build(segments: [GeneratedTranscriptSegment]) -> String {
        let cues = buildCues(from: segments)
        var lines = ["WEBVTT", ""]
        for (index, cue) in cues.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(formatTimestamp(ms: cue.startMs)) --> \(formatTimestamp(ms: cue.endMs))")
            for line in cue.lines {
                lines.append(line)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func buildCues(from segments: [GeneratedTranscriptSegment]) -> [(startMs: Int64, endMs: Int64, lines: [String])] {
        struct TimedWord {
            let word: String
            let startMs: Int64
            let endMs: Int64
        }

        var timedWords: [TimedWord] = []
        for seg in segments {
            let t = seg.text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if seg.words.isEmpty {
                let tokens = t.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard !tokens.isEmpty else { continue }
                let span = seg.endMs - seg.startMs
                let step = tokens.count > 1 ? span / Int64(tokens.count) : 0
                for (i, token) in tokens.enumerated() {
                    let s = seg.startMs + Int64(i) * step
                    let e = i == tokens.count - 1 ? seg.endMs : s + step
                    timedWords.append(TimedWord(word: token, startMs: s, endMs: e))
                }
            } else {
                for w in seg.words {
                    timedWords.append(TimedWord(word: w.word, startMs: w.startMs, endMs: w.endMs))
                }
            }
        }

        var cues: [(startMs: Int64, endMs: Int64, lines: [String])] = []
        var cueLines: [(text: String, startMs: Int64, endMs: Int64)] = []
        var lineWords: [TimedWord] = []
        var lineCharCount = 0

        func flushLine() {
            guard !lineWords.isEmpty else { return }
            let text = lineWords.map(\.word).joined(separator: " ")
            let start = lineWords.first!.startMs
            let end = lineWords.last!.endMs
            cueLines.append((text, start, end))
            lineWords = []
            lineCharCount = 0
        }

        func flushCue() {
            guard !cueLines.isEmpty else { return }
            let start = cueLines.first!.startMs
            let end = cueLines.last!.endMs
            cues.append((start, end, cueLines.map(\.text)))
            cueLines = []
        }

        for w in timedWords {
            let add = (lineWords.isEmpty ? 0 : 1) + w.word.count
            if lineCharCount + add > maxCharsPerLine, !lineWords.isEmpty {
                flushLine()
                if cueLines.count >= maxLinesPerCue {
                    flushCue()
                }
            }
            lineWords.append(w)
            lineCharCount += (lineWords.count == 1 ? 0 : 1) + w.word.count

            let cueStart = cueLines.first?.startMs ?? lineWords.first!.startMs
            let cueEnd = lineWords.last!.endMs
            if !cueLines.isEmpty, (cueEnd - cueStart) > maxCueDurationMs {
                flushCue()
            }
        }
        flushLine()
        flushCue()
        return cues
    }

    private static func formatTimestamp(ms: Int64) -> String {
        let totalSeconds = Int(ms) / 1_000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let millis = Int(ms) % 1_000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }
}
