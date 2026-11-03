import Foundation
import Observation

/// Owns the transfers.
///
/// Progressive files run on a **background** `URLSession`, so they keep going while the app
/// is suspended or terminated, and survive a relaunch (tasks are re-matched through
/// `taskDescription`). HLS streams are orchestrated in-process by `HLSDownloader` and pause
/// with the app.
@MainActor
@Observable
final class DownloadManager: NSObject {

    static let shared = DownloadManager()

    private var session: URLSession!
    private let library = LibraryStore.shared

    private var activeTasks: [UUID: URLSessionTask] = [:]
    private var hlsTasks: [UUID: Task<Void, Never>] = [:]
    private let registry = TaskRegistry()

    private override init() {
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: BackgroundSessionBridge.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.httpMaximumConnectionsPerHost = 4
        config.httpAdditionalHeaders = ["User-Agent": LinkResolver.userAgent]

        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        Task { @MainActor in await reconcileWithSystem() }
    }

    // MARK: - Public API

    func start(_ media: ResolvedMedia) {
        let record = DownloadRecord(media: media)
        library.upsert(record)
        begin(record: record, media: media)
    }

    func retry(_ record: DownloadRecord) {
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
            contentLength: record.bytesExpected > 0 ? record.bytesExpected : nil,
            pageURL: record.sourceURL
        )
        begin(record: refreshed, media: media)
    }

    /// Resume a paused background download, or restart when there is nothing to resume.
    func resume(_ record: DownloadRecord) {
        let hasResumeData = record.state == .paused
            && record.kind == .progressive
            && FileManager.default.fileExists(atPath: AppPaths.resumeDataURL(recordID: record.id).path)
        guard hasResumeData else {
            retry(record)
            return
        }
        let media = ResolvedMedia(
            kind: record.kind,
            url: record.remoteURL,
            title: record.title,
            contentLength: record.bytesExpected > 0 ? record.bytesExpected : nil,
            pageURL: record.sourceURL
        )
        library.update(record.id) {
            $0.state = .running
            $0.errorMessage = nil
        }
        begin(record: library.record(id: record.id) ?? record, media: media)
    }

    func cancel(_ recordID: UUID) {
        discardResumeData(recordID: recordID)
        if let task = activeTasks[recordID] {
            task.cancel()
            activeTasks[recordID] = nil
        }
        if let task = hlsTasks[recordID] {
            task.cancel()
            hlsTasks[recordID] = nil
        }
        library.update(recordID) { record in
            record.state = .cancelled
            record.errorMessage = "Cancelled."
        }
    }

    func pause(_ recordID: UUID) {
        guard let task = activeTasks[recordID] as? URLSessionDownloadTask else { return }
        // Flip the state first: the cancel delegate callback must not treat this as a user cancel.
        library.update(recordID) { record in
            record.state = .paused
            record.errorMessage = "Pausing…"
        }
        task.cancel { [weak self] resumeData in
            guard let self else { return }
            if let resumeData {
                try? resumeData.write(to: AppPaths.resumeDataURL(recordID: recordID), options: .atomic)
            }
            Task { @MainActor in
                self.activeTasks[recordID] = nil
                self.library.update(recordID) { record in
                    record.errorMessage = resumeData == nil
                        ? "Paused. Tap resume to start over."
                        : "Paused. Tap resume to continue."
                }
            }
        }
    }

    // MARK: - Scheduling

    private func begin(record: DownloadRecord, media: ResolvedMedia) {
        switch media.kind {
        case .progressive:
            let resumeURL = AppPaths.resumeDataURL(recordID: record.id)
            let task: URLSessionDownloadTask
            if let data = try? Data(contentsOf: resumeURL) {
                task = session.downloadTask(withResumeData: data)
            } else {
                var request = URLRequest(url: media.url)
                media.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                task = session.downloadTask(with: request)
            }
            task.taskDescription = Self.taskDescription(recordID: record.id, fileExtension: media.fileExtension)
            registry.register(TaskRegistry.Entry(recordID: record.id, fileExtension: media.fileExtension),
                              for: task.taskIdentifier)
            activeTasks[record.id] = task
            library.update(record.id) { $0.state = .running }
            task.resume()

        case .hls:
            startHLS(record: record, media: media)
        }
    }

    private func startHLS(record: DownloadRecord, media: ResolvedMedia) {
        let recordID = record.id
        let downloader = HLSDownloader(headers: media.httpHeaders)
        let relay = ProgressRelay(manager: self, recordID: recordID)
        library.update(recordID) { $0.state = .running }

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
        library.update(recordID) { record in
            if record.state == .queued { record.state = .running }
            record.bytesReceived = received
            if expected > 0 { record.bytesExpected = expected }
        }
    }

    func finish(recordID: UUID, fileName: String, bytes: Int64) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        discardResumeData(recordID: recordID)
        library.update(recordID) { record in
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
        library.update(recordID) { record in
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
        library.update(recordID) { record in
            guard record.state != .paused else { return }
            record.state = .cancelled
            record.errorMessage = "Cancelled."
        }
    }

    private func markPaused(recordID: UUID, message: String) {
        activeTasks[recordID] = nil
        library.update(recordID) { record in
            record.state = .paused
            record.errorMessage = message
        }
    }

    // MARK: - Reconciliation

    /// Runs once at launch: anything the app thinks is downloading but the system doesn't
    /// know about was interrupted (app was killed, HLS job died, …).
    private func reconcileWithSystem() async {
        let tasks = await session.allTasks
        var live = Set<UUID>()
        for task in tasks {
            guard let entry = Self.entry(for: task) else { continue }
            live.insert(entry.recordID)
            registry.register(entry, for: task.taskIdentifier)
            if let record = library.record(id: entry.recordID), record.state != .running {
                library.update(entry.recordID) { $0.state = .running }
            }
        }

        for record in library.records where record.isActive && !live.contains(record.id) {
            let hasResumeData = FileManager.default.fileExists(atPath: AppPaths.resumeDataURL(recordID: record.id).path)
            library.update(record.id) {
                $0.state = hasResumeData ? .paused : .failed
                $0.errorMessage = hasResumeData
                    ? "Paused. Tap resume to continue."
                    : "Interrupted. Tap retry to start over."
            }
        }
    }

    // MARK: - Housekeeping

    private func discardResumeData(recordID: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.resumeDataURL(recordID: recordID))
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
        library.update(recordID) { record in
            if let thumbnail { record.thumbnailName = thumbnail }
            if let duration { record.duration = duration }
        }
    }

    // MARK: - Task descriptions

    /// Background tasks are re-delivered after a relaunch, so the record identity travels
    /// inside `taskDescription` rather than in memory.
    private static func taskDescription(recordID: UUID, fileExtension: String) -> String {
        "\(recordID.uuidString)|\(fileExtension)"
    }

    nonisolated private static func entry(for task: URLSessionTask) -> TaskRegistry.Entry? {
        guard let description = task.taskDescription else { return nil }
        let parts = description.split(separator: "|")
        guard let first = parts.first, let recordID = UUID(uuidString: String(first)) else { return nil }
        let ext = parts.count > 1 ? String(parts[1]) : "mp4"
        return TaskRegistry.Entry(recordID: recordID, fileExtension: ext)
    }
}

// MARK: - URLSession delegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let entry = Self.entry(for: downloadTask) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        Task { @MainActor [weak self] in
            self?.updateProgress(recordID: entry.recordID, received: totalBytesWritten, expected: expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let entry = Self.entry(for: downloadTask) else { return }

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
        guard let error else { return }
        guard let entry = Self.entry(for: task) else { return }

        let nsError = error as NSError
        let isCancel = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        if isCancel {
            // `pause(_:)` writes resume data itself; a plain cancel keeps whatever exists.
            Task { @MainActor [weak self] in
                self?.activeTasks[entry.recordID] = nil
                self?.markCancelled(recordID: entry.recordID)
            }
            return
        }

        if let resumeData {
            try? resumeData.write(to: AppPaths.resumeDataURL(recordID: entry.recordID), options: .atomic)
            Task { @MainActor [weak self] in
                self?.markPaused(recordID: entry.recordID, message: "Connection lost. Tap resume to continue.")
            }
        } else {
            Task { @MainActor [weak self] in
                self?.fail(recordID: entry.recordID, message: Self.readableMessage(for: nsError))
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let handler = BackgroundSessionBridge.consume() else { return }
        DispatchQueue.main.async { handler() }
    }

    private static func readableMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return "You appear to be offline. Tap resume when you're back."
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

/// Fast in-memory lookup for the current process; `taskDescription` covers relaunches.
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
