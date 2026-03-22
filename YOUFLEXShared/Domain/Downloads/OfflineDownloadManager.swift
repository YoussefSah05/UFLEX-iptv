import Foundation

final class OfflineDownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let database: AppDatabase
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(database: AppDatabase) {
        self.database = database
        super.init()
    }

    func startDownload(for presentation: PlaybackPresentation) async throws {
        guard presentation.kind != .live else {
            throw URLError(.unsupportedURL)
        }

        let downloadId = Self.downloadIdentifier(for: presentation)
        if let existing = try database.fetchDownload(id: downloadId),
           existing.status == "completed" || existing.status == "downloading" {
            return
        }

        let now = Date()
        let record = DownloadRecord(
            id: downloadId,
            contentId: presentation.id,
            contentType: presentation.kind.rawValue,
            title: presentation.title,
            sourceUrl: presentation.streamURL.absoluteString,
            localRelativePath: nil,
            status: "queued",
            bytesDownloaded: 0,
            expectedBytes: 0,
            failureMessage: nil,
            createdAt: now,
            updatedAt: now
        )
        try database.upsertDownload(record)

        let task = session.downloadTask(with: presentation.streamURL)
        task.taskDescription = downloadId
        task.resume()

        try database.updateDownloadStatus(id: downloadId, status: "downloading", bytesDownloaded: 0, expectedBytes: 0, failureMessage: nil)
        NotificationCenter.default.post(name: .youflexDownloadsDidChange, object: nil)
    }

    static func downloadIdentifier(for presentation: PlaybackPresentation) -> String {
        "download-\(presentation.kind.rawValue)-\(presentation.id)"
    }

    private func finalizeDownload(taskId: String, location: URL) throws {
        guard let record = try database.fetchDownload(id: taskId) else {
            return
        }

        let sourceURL = URL(string: record.sourceUrl)
        let fileExtension = sourceURL?.pathExtension.isEmpty == false ? sourceURL?.pathExtension ?? "mp4" : "mp4"
        let destinationURL = try AppPaths.downloadsDirectory()
            .appendingPathComponent("\(record.id).\(fileExtension)")

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: location, to: destinationURL)
        let relativePath = try AppPaths.relativePath(for: destinationURL)
        try database.updateDownloadCompletion(id: taskId, localRelativePath: relativePath)
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else {
            return
        }
        try? database.updateDownloadStatus(
            id: id,
            status: "downloading",
            bytesDownloaded: totalBytesWritten,
            expectedBytes: totalBytesExpectedToWrite,
            failureMessage: nil
        )
        NotificationCenter.default.post(name: .youflexDownloadsDidChange, object: nil)
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else {
            return
        }
        do {
            try finalizeDownload(taskId: id, location: location)
        } catch {
            try? database.updateDownloadStatus(
                id: id,
                status: "failed",
                bytesDownloaded: downloadTask.countOfBytesReceived,
                expectedBytes: downloadTask.countOfBytesExpectedToReceive,
                failureMessage: error.localizedDescription
            )
        }
        NotificationCenter.default.post(name: .youflexDownloadsDidChange, object: nil)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let id = task.taskDescription else {
            return
        }
        if let error {
            try? database.updateDownloadStatus(
                id: id,
                status: "failed",
                bytesDownloaded: task.countOfBytesReceived,
                expectedBytes: task.countOfBytesExpectedToReceive,
                failureMessage: error.localizedDescription
            )
            NotificationCenter.default.post(name: .youflexDownloadsDidChange, object: nil)
        }
    }
}
