import Foundation
import Observation

/// Owns the actual transfers: progressive files through `URLSessionDownloadTask`,
/// HLS streams through `HLSDownloader`.
@MainActor
@Observable
final class DownloadManager: NSObject {

    private var session: URLSession!
    private weak var library: LibraryStore?

    private let registry = TaskRegistry()
    private var activeTasks: [UUID: URLSessionTask] = [:]
    private var hlsTasks: [UUID: Task<Void, Never>] = [:]

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 4
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = ["User-Agent": LinkResolver.userAgent]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func attach(library: LibraryStore) {
        self.library = library
    }

    // MARK: - Public API

    func start(_ media: ResolvedMedia) {
        guard let library else { return }
        var record = DownloadRecord(media: media)
        library.upsert(record)
        record = library.record(id: record.id) ?? record
        begin(record: record, media: media)
    }

    func retry(_ record: DownloadRecord) {
        guard let library else { return }
        var refreshed = record
        refreshed.state = .queued
        refreshed.bytesReceived = 0
        refreshed.errorMessage = nil
        refreshed.fileName = nil
        refreshed.thumbnailName = nil
        refreshed.createdAt = Date()
        library.upsert(refreshed)

        let media = ResolvedMedia(
            kind: record.kind,
            url: record.remoteURL,
            title: record.title,
            mimeType: nil,
            contentLength: record.bytesExpected > 0 ? record.bytesExpected : nil,
            pageURL: record.sourceURL
        )
        begin(record: refreshed, media: media)
    }

    func cancel(_ recordID: UUID) {
        if let task = activeTasks[recordID] {
            task.cancel()
            activeTasks[recordID] = nil
        }
        if let task = hlsTasks[recordID] {
            task.cancel()
            hlsTasks[recordID] = nil
        }
        library?.update(recordID) { record in
            record.state = .cancelled
            record.errorMessage = "Cancelled."
        }
    }

    // MARK: - Scheduling

    private func begin(record: DownloadRecord, media: ResolvedMedia) {
        switch media.kind {
        case .progressive:
            var request = URLRequest(url: media.url)
            media.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let task = session.downloadTask(with: request)
            registry.register(TaskRegistry.Entry(recordID: record.id, fileExtension: media.fileExtension),
                              for: task.taskIdentifier)
            activeTasks[record.id] = task
            library?.update(record.id) { $0.state = .running }
            task.resume()
        case .hls:
            startHLS(record: record, media: media)
        }
    }

    private func startHLS(record: DownloadRecord, media: ResolvedMedia) {
        let recordID = record.id
        let downloader = HLSDownloader(headers: media.httpHeaders)
        let relay = ProgressRelay(manager: self, recordID: recordID)
        library?.update(recordID) { $0.state = .running }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let fileName = try await downloader.download(
                    playlistURL: media.url,
                    recordID: recordID,
                    fileName: { ext in "\(recordID.uuidString).\(ext)" },
                    progress: { received, expected in
                        relay.report(received, expected)
                    }
                )
                let bytes = (try? FileManager.default.attributesOfItem(atPath: AppPaths.mediaURL(fileName: fileName).path)[.size] as? NSNumber)?.int64Value ?? 0
                await self?.finish(recordID: recordID, fileName: fileName, bytes: bytes)
            } catch is CancellationError {
                await self?.markCancelled(recordID: recordID)
            } catch {
                await self?.fail(recordID: recordID, message: error.localizedDescription)
            }
        }
        hlsTasks[recordID] = task
    }

    // MARK: - State changes

    fileprivate func updateProgress(recordID: UUID, received: Int64, expected: Int64) {
        library?.update(recordID) { record in
            if record.state == .queued { record.state = .running }
            record.bytesReceived = received
            if expected > 0 { record.bytesExpected = expected }
        }
    }

    func finish(recordID: UUID, fileName: String, bytes: Int64) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        library?.update(recordID) { record in
            record.state = .finished
            record.fileName = fileName
            record.bytesReceived = bytes
            if record.bytesExpected <= 0 { record.bytesExpected = bytes }
            record.errorMessage = nil
        }
        generateMetadata(recordID: recordID, fileName: fileName)
    }

    private func fail(recordID: UUID, message: String?) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        cleanTemporaryFiles(recordID: recordID)
        library?.update(recordID) { record in
            if record.state != .cancelled {
                record.state = .failed
                record.errorMessage = message ?? "Download failed."
            }
        }
    }

    private func markCancelled(recordID: UUID) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        cleanTemporaryFiles(recordID: recordID)
        library?.update(recordID) { record in
            record.state = .cancelled
            record.errorMessage = "Cancelled."
        }
    }

    private func cleanTemporaryFiles(recordID: UUID) {
        let prefix = recordID.uuidString
        let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.temporary,
                                                                 includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func generateMetadata(recordID: UUID, fileName: String) {
        let fileURL = AppPaths.mediaURL(fileName: fileName)
        Task.detached(priority: .utility) { [weak self] in
            let thumbnail = await ThumbnailService.makeThumbnail(for: fileURL, recordID: recordID)
            let duration = await ThumbnailService.duration(of: fileURL)
            await self?.applyMetadata(recordID: recordID, thumbnail: thumbnail, duration: duration)
        }
    }

    private func applyMetadata(recordID: UUID, thumbnail: String?, duration: Double?) {
        library?.update(recordID) { record in
            if let thumbnail { record.thumbnailName = thumbnail }
            if let duration { record.duration = duration }
        }
    }
}

// MARK: - URLSession delegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let taskID = downloadTask.taskIdentifier
        guard let entry = registry.entry(for: taskID) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        Task { @MainActor [weak self] in
            self?.updateProgress(recordID: entry.recordID, received: totalBytesWritten, expected: expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let taskID = downloadTask.taskIdentifier
        guard let entry = registry.entry(for: taskID) else { return }

        let fileName = "\(entry.recordID.uuidString).\(entry.fileExtension)"
        let destination = AppPaths.mediaURL(fileName: fileName)
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            Task { @MainActor [weak self] in
                self?.finish(recordID: entry.recordID, fileName: fileName, bytes: bytes)
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.fail(recordID: entry.recordID, message: "Could not save the file: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        guard let entry = registry.entry(for: taskID) else { return }
        registry.remove(taskID)
        guard let error else { return }

        let nsError = error as NSError
        let isCancel = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        Task { @MainActor [weak self] in
            if isCancel {
                self?.markCancelled(recordID: entry.recordID)
            } else {
                self?.fail(recordID: entry.recordID, message: Self.readableMessage(for: nsError))
            }
        }
    }

    private static func readableMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return "You appear to be offline."
        case NSURLErrorTimedOut:
            return "The server took too long to respond."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "The server's security certificate couldn't be verified."
        case NSURLErrorUnsupportedURL:
            return "That link can't be downloaded directly."
        default:
            return error.localizedDescription
        }
    }
}

/// Hands progress updates from a detached task back to the main actor without
/// capturing `self` in a concurrent closure.
private final class ProgressRelay: @unchecked Sendable {
    private weak var manager: DownloadManager?
    private let recordID: UUID

    init(manager: DownloadManager, recordID: UUID) {
        self.manager = manager
        self.recordID = recordID
    }

    func report(_ received: Int64, _ expected: Int64) {
        Task { @MainActor in
            manager?.updateProgress(recordID: recordID, received: received, expected: expected)
        }
    }
}

// MARK: - Task registry

/// Bridges the non-isolated URLSession delegate callbacks back to record identities.
final class TaskRegistry: @unchecked Sendable {
    struct Entry {
        var recordID: UUID
        var fileExtension: String
    }

    private var entries: [Int: Entry] = [:]
    private let lock = NSLock()

    func register(_ entry: Entry, for taskID: Int) {
        lock.lock(); defer { lock.unlock() }
        entries[taskID] = entry
    }

    func entry(for taskID: Int) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[taskID]
    }

    func remove(_ taskID: Int) {
        lock.lock(); defer { lock.unlock() }
        entries[taskID] = nil
    }
}
