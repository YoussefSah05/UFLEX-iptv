import Foundation

enum ProgressTracker {
    static let completionThreshold = 0.92
    static let minimumPersistPositionMs: Int64 = 5_000
    static let minimumResumePositionMs: Int64 = 15_000

    static func watchedPercent(positionMs: Int64, durationMs: Int64) -> Double {
        guard durationMs > 0 else { return 0 }
        return min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }

    static func isCompleted(positionMs: Int64, durationMs: Int64) -> Bool {
        watchedPercent(positionMs: positionMs, durationMs: durationMs) >= completionThreshold
    }

    static func shouldPersist(positionMs: Int64, durationMs: Int64) -> Bool {
        durationMs > 0 && positionMs >= minimumPersistPositionMs
    }

    static func resumePositionMs(positionMs: Int64, durationMs: Int64, completed: Bool) -> Int64 {
        guard !completed else { return 0 }
        guard shouldPersist(positionMs: positionMs, durationMs: durationMs) else { return 0 }
        return positionMs
    }

    static func progressText(positionMs: Int64, durationMs: Int64, completed: Bool) -> String {
        if completed {
            return "Completed"
        }

        guard shouldPersist(positionMs: positionMs, durationMs: durationMs) else {
            return "Not started"
        }

        let percent = Int((watchedPercent(positionMs: positionMs, durationMs: durationMs) * 100).rounded())
        return "Resume at \(format(milliseconds: positionMs)) · \(percent)%"
    }

    static func format(milliseconds: Int64) -> String {
        let totalSeconds = max(Int(milliseconds / 1_000), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
