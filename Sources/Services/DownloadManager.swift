import Foundation
import Observation

/// Owns the transfers and the queue.
///
/// Progressive files run on a **background** `URLSession`, so they keep going while the app is
/// suspended or terminated and are re-matched after a relaunch through `taskDescription`.
/// HLS jobs run in-process but write every finished segment to disk, so pausing, a crash, or a
/// relaunch can pick up where they stopped.
@MainActor
@Observable
final class DownloadManager: NSObject {

    static let shared = DownloadManager()

    private var session: URLSession!
    private let library = LibraryStore.shared
    private let settings = AppSettings.shared
    private let network = NetworkMonitor.shared

    private var activeTasks: [UUID: URLSessionTask] = [:]
    private var hlsTasks: [UUID: Task<Void, Never>] = [:]
    private var pending: [UUID] = []
    private let registry = TaskRegistry()
    private var networkObserver: NSObjectProtocol?
    /// When each record last had its media address re-resolved, so a server that keeps
    /// rejecting one cannot turn into a re-resolve loop.
    private var lastSourceRefresh: [UUID: Date] = [:]

    /// Minimum gap between automatic re-resolves for one record.
    static let sourceRefreshCooldown: TimeInterval = 60

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

        networkObserver = NotificationCenter.default.addObserver(
            forName: .fluxKitNetworkChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.networkChanged() }
        }

        Task { @MainActor in await reconcileWithSystem() }
    }

    // MARK: - Public API

    func start(_ media: ResolvedMedia) {
        let record = DownloadRecord(media: media)
        library.upsert(record)
        enqueue(record.id)
    }

    func retry(_ record: DownloadRecord) {
        discardResumeData(recordID: record.id)
        AppPaths.removeHLSWork(recordID: record.id)
        // An explicit retry is a fresh start, so it may re-resolve the page immediately.
        lastSourceRefresh[record.id] = nil
        var refreshed = record
        refreshed.state = .queued
        refreshed.bytesReceived = 0
        refreshed.errorMessage = nil
        refreshed.fileName = nil
        refreshed.thumbnailName = nil
        refreshed.lastPosition = nil
        refreshed.createdAt = Date()
        library.upsert(refreshed)
        enqueue(refreshed.id)
    }

    /// Resume a paused transfer. HLS reuses its downloaded segments; direct files use resume data.
    func resume(_ record: DownloadRecord) {
        let canResumeProgressive = record.kind == .progressive
            && FileManager.default.fileExists(atPath: AppPaths.resumeDataURL(recordID: record.id).path)
        let canResumeHLS = record.kind == .hls && AppPaths.hlsHasProgress(recordID: record.id)
        guard canResumeProgressive || canResumeHLS else {
            retry(record)
            return
        }
        lastSourceRefresh[record.id] = nil
        library.update(record.id) { item in
            item.state = .queued
            item.errorMessage = nil
        }
        enqueue(record.id)
    }

    func pause(_ recordID: UUID) {
        pending.removeAll { $0 == recordID }

        if let task = activeTasks[recordID] as? URLSessionDownloadTask {
            // Flip the state first: the cancel delegate callback must not treat this as a user cancel.
            library.update(recordID) { record in
                record.state = .paused
                record.errorMessage = L("Pausing…", "正在暂停…")
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
                            ? L("Paused. Tap resume to start over.", "已暂停。点继续重新下载。")
                            : L("Paused. Tap resume to continue.", "已暂停。点继续接着下载。")
                    }
                    self.pump()
                }
            }
            activeTasks[recordID] = nil
            pump()
            return
        }

        if let task = hlsTasks[recordID] {
            library.update(recordID) { record in
                record.state = .paused
                record.errorMessage = L("Paused. Tap resume to continue.", "已暂停。点继续接着下载。")
            }
            task.cancel()
            hlsTasks[recordID] = nil
            pump()
            return
        }

        // Still waiting in the queue.
        if let record = library.record(id: recordID), record.state == .queued {
            library.update(recordID) { item in
                item.state = .paused
                item.errorMessage = L("Paused. Tap resume to continue.", "已暂停。点继续接着下载。")
            }
            pump()
        }
    }

    func cancel(_ recordID: UUID) {
        pending.removeAll { $0 == recordID }
        discardResumeData(recordID: recordID)
        if let task = activeTasks[recordID] {
            task.cancel()
            activeTasks[recordID] = nil
        }
        if let task = hlsTasks[recordID] {
            task.cancel()
            hlsTasks[recordID] = nil
        }
        AppPaths.removeHLSWork(recordID: recordID)
        library.update(recordID) { record in
            record.state = .cancelled
            record.errorMessage = L("Cancelled.", "已取消。")
        }
        pump()
    }

    /// Called when the network path or the queue settings change.
    func networkChanged() {
        pump()
    }

    // MARK: - Queue

    private var runningCount: Int {
        activeTasks.count + hlsTasks.count
    }

    private var isWaitingForNetwork: Bool {
        !network.isConnected || (settings.wifiOnly && !network.isOnWiFi)
    }

    private func enqueue(_ recordID: UUID) {
        guard library.record(id: recordID) != nil else { return }
        if !pending.contains(recordID) {
            pending.append(recordID)
        }
        pump()
    }

    private func pump() {
        guard !isWaitingForNetwork else {
            markQueueWaitingForNetwork()
            return
        }

        var safety = 0
        let concurrency = ProEntitlements.effectiveConcurrency(
            configured: settings.maxConcurrentDownloads,
            isPro: ProStore.shared.isPro
        )
        while runningCount < concurrency, !pending.isEmpty, safety < 32 {
            safety += 1
            let recordID = pending.removeFirst()
            guard let record = library.record(id: recordID),
                  record.state == .queued || record.state == .paused else { continue }
            launch(record: record)
        }
    }

    private func markQueueWaitingForNetwork() {
        for recordID in pending {
            library.update(recordID) { record in
                guard record.state == .queued else { return }
                record.errorMessage = L("Waiting for Wi-Fi.", "等待 Wi-Fi。") // replaced below when offline
                if !self.network.isConnected {
                    record.errorMessage = L("Waiting for a connection.", "等待网络连接。")
                }
            }
        }
    }

    private func launch(record: DownloadRecord) {
        library.update(record.id) { item in
            item.state = .running
            item.errorMessage = nil
        }
        let media = Self.media(from: record)
        switch record.kind {
        case .progressive:
            startProgressive(record: record, media: media)
        case .hls:
            startHLS(record: record, media: media)
        }
    }

    private func startProgressive(record: DownloadRecord, media: ResolvedMedia) {
        let resumeURL = AppPaths.resumeDataURL(recordID: record.id)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL) {
            task = session.downloadTask(withResumeData: data)
        } else {
            var request = URLRequest(url: media.url)
            media.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            request.allowsCellularAccess = !settings.wifiOnly
            task = session.downloadTask(with: request)
        }
        task.taskDescription = Self.taskDescription(recordID: record.id, fileExtension: media.fileExtension)
        registry.register(
            TaskRegistry.Entry(recordID: record.id, fileExtension: media.fileExtension),
            for: task.taskIdentifier
        )
        activeTasks[record.id] = task
        task.resume()
    }

    private func startHLS(record: DownloadRecord, media: ResolvedMedia) {
        let recordID = record.id
        let downloader = HLSDownloader(headers: media.httpHeaders)
        let relay = ProgressRelay(manager: self, recordID: recordID)

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
                let bytes = (try? FileManager.default.attributesOfItem(
                    atPath: AppPaths.mediaURL(fileName: fileName).path)[.size] as? NSNumber
                )?.int64Value ?? 0
                await self?.finish(recordID: recordID, fileName: fileName, bytes: bytes)
            } catch is CancellationError {
                await self?.hlsTaskStopped(recordID: recordID)
            } catch {
                await self?.fail(recordID: recordID, message: error.localizedDescription)
            }
        }
        hlsTasks[recordID] = task
    }

    private func hlsTaskStopped(recordID: UUID) {
        hlsTasks[recordID] = nil
        if let record = library.record(id: recordID), record.state == .paused || record.state == .cancelled {
            pump()
            return
        }
        markCancelled(recordID: recordID)
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
        pending.removeAll { $0 == recordID }
        lastSourceRefresh[recordID] = nil
        discardResumeData(recordID: recordID)
        AppPaths.removeHLSWork(recordID: recordID)

        // Files.app shows this name, so use the human title instead of the UUID.
        let title = library.record(id: recordID)?.title ?? L("Video", "视频")
        let finalName = FileNames.adopt(fileName: fileName, title: title, recordID: recordID)

        library.update(recordID) { record in
            record.state = .finished
            record.fileName = finalName
            record.bytesReceived = bytes
            if record.bytesExpected <= 0 { record.bytesExpected = bytes }
            record.errorMessage = nil
        }
        if let title = library.record(id: recordID)?.title {
            DownloadNotifications.finished(title: title)
        }
        generateMetadata(recordID: recordID, fileName: finalName)
        pump()
    }

    private func fail(recordID: UUID, message: String?) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        pending.removeAll { $0 == recordID }
        cleanTemporaryFiles(recordID: recordID)
        let text = message ?? L("Download failed.", "下载失败。")
        library.update(recordID) { record in
            if record.state != .cancelled && record.state != .paused {
                record.state = .failed
                record.errorMessage = text
            }
        }
        if let record = library.record(id: recordID), record.state == .failed {
            DownloadNotifications.failed(title: record.title, reason: text)
        }
        pump()
    }

    private func markCancelled(recordID: UUID) {
        hlsTasks[recordID] = nil
        activeTasks[recordID] = nil
        pending.removeAll { $0 == recordID }
        cleanTemporaryFiles(recordID: recordID)
        library.update(recordID) { record in
            guard record.state != .paused else { return }
            record.state = .cancelled
            record.errorMessage = L("Cancelled.", "已取消。")
        }
        pump()
    }

    private func markPaused(recordID: UUID, message: String) {
        activeTasks[recordID] = nil
        library.update(recordID) { record in
            record.state = .paused
            record.errorMessage = message
        }
        pump()
    }

    // MARK: - Lapsed media addresses

    /// Signed playback addresses (see `SiteExtractor`) stop working after a few minutes — which
    /// is exactly what a long pause looks like. The *page* link those addresses came from still
    /// resolves, so instead of failing the download the manager asks `LinkResolver` for a fresh
    /// address and starts the transfer over.

    /// Status codes that mean "this address is no longer good for you": the token lapsed
    /// (401/403/451), the object is gone (404/410), or the range we asked for no longer fits
    /// (412/416, typical when stale resume data is replayed against a re-signed URL).
    nonisolated static let rejectedStatusCodes: Set<Int> = [401, 403, 404, 410, 412, 416, 451]

    /// - Returns: `true` when re-resolving makes sense: the record was scraped from a page
    ///   (so `sourceURL` is not the media address itself), we're online, and the previous
    ///   attempt is older than `sourceRefreshCooldown`.
    nonisolated static func canRefreshSource(for record: DownloadRecord,
                                             lastRefresh: Date?,
                                             isOnline: Bool,
                                             now: Date = Date()) -> Bool {
        guard record.kind == .progressive else { return false }
        guard record.sourceURL != record.remoteURL else { return false }
        guard isOnline else { return false }
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < sourceRefreshCooldown { return false }
        return true
    }

    /// - Returns: `true` when the transfer was restarted with a new address.
    private func recoverFromRejectedURL(recordID: UUID) async -> Bool {
        guard let record = library.record(id: recordID),
              // Never resurrect a transfer the user paused or cancelled in the meantime.
              record.state == .running || record.state == .queued,
              Self.canRefreshSource(for: record,
                                    lastRefresh: lastSourceRefresh[recordID],
                                    isOnline: network.isConnected) else {
            return false
        }

        lastSourceRefresh[recordID] = Date()
        #if DEBUG
        NSLog("REFRESH: re-resolving \(record.sourceURL.absoluteString) for \(recordID.uuidString.prefix(8))")
        #endif

        let media: ResolvedMedia
        do {
            media = try await LinkResolver().resolve(input: record.sourceURL.absoluteString)
        } catch {
            #if DEBUG
            NSLog("REFRESH: failed — \(error.localizedDescription)")
            #endif
            return false
        }

        // Unchanged address means the site is not handing out a new one; retrying would just
        // hit the same wall, so let the caller report the failure.
        guard media.url != record.remoteURL else { return false }

        // Resume data is bound to the old request, so it would replay the dead address forever.
        discardResumeData(recordID: recordID)
        library.update(recordID) { item in
            item.remoteURL = media.url
            if let mime = media.mimeType { item.mimeType = mime }
            if !media.httpHeaders.isEmpty { item.httpHeaders = media.httpHeaders }
            if let thumbnail = media.thumbnailURL { item.thumbnailRemoteURL = thumbnail }
            if let length = media.contentLength, length > 0 { item.bytesExpected = length }
            item.bytesReceived = 0
            item.state = .queued
            item.errorMessage = nil
        }
        enqueue(recordID)
        return true
    }

    /// A response the server refused. The body it came with is an error page, never the video,
    /// so it is thrown away instead of being saved as if the download had succeeded.
    private func handleRejectedResponse(recordID: UUID, status: Int) async {
        activeTasks[recordID] = nil
        pending.removeAll { $0 == recordID }
        #if DEBUG
        NSLog("REFRESH: transfer rejected (HTTP \(status)) for \(recordID.uuidString.prefix(8))")
        #endif
        if await recoverFromRejectedURL(recordID: recordID) { return }
        fail(recordID: recordID, message: Self.message(forRejectedStatus: status))
    }

    /// The message the user sees when the transfer was refused and no fresh address could be
    /// fetched — status-specific, because "the link expired" is wrong for a deleted file.
    nonisolated static func message(forRejectedStatus status: Int) -> String {
        switch status {
        case 404, 410:
            return L("The server no longer has that file.", "服务器上已经没有这个文件了。")
        case 412, 416:
            return L("The server couldn't continue this download. Tap retry to start over.",
                     "服务器无法继续这个下载。点重试重新开始。")
        default:
            return expiredLinkMessage
        }
    }

    nonisolated private static var expiredLinkMessage: String {
        L("The site's playback link had expired and a new one couldn't be fetched. Paste the page link again to refresh it.",
          "网站的播放地址已过期，暂时没能换到新的。重新粘贴一遍页面链接就能刷新。")
    }

    /// `NSURLErrorBadServerResponse` is how a rejected signed address surfaces when the system
    /// fails the task instead of handing over the body (`didFinishDownloadingTo` covers the rest).
    nonisolated static func isRejectedAddress(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && error.code == NSURLErrorBadServerResponse
    }

    /// Logged for the debug harness; kept separate so the delegate code stays readable.
    nonisolated static func rejectionStatus(from response: URLResponse?) -> Int? {
        guard let http = response as? HTTPURLResponse else { return nil }
        guard !(200..<300).contains(http.statusCode) else { return nil }
        return http.statusCode
    }

    // MARK: - Reconciliation

    /// Runs once at launch: anything the app thinks is running but the system doesn't know about
    /// was interrupted (app killed, HLS job died, …). Queued records simply rejoin the queue.
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

        for record in library.records where record.state == .queued && !live.contains(record.id) {
            if !pending.contains(record.id) { pending.append(record.id) }
        }

        for record in library.records where record.state == .running && !live.contains(record.id) {
            let hasResumeData = FileManager.default.fileExists(
                atPath: AppPaths.resumeDataURL(recordID: record.id).path)
            let canResume = record.kind == .hls
                ? AppPaths.hlsHasProgress(recordID: record.id)
                : hasResumeData
            library.update(record.id) {
                $0.state = canResume ? .paused : .failed
                $0.errorMessage = canResume
                    ? L("Paused. Tap resume to continue.", "已暂停。点继续接着下载。")
                    : L("Interrupted. Tap retry to start over.", "下载被打断了。点重试重新开始。")
            }
        }

        pump()
    }

    // MARK: - Housekeeping

    private func discardResumeData(recordID: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.resumeDataURL(recordID: recordID))
    }

    private func cleanTemporaryFiles(recordID: UUID) {
        let prefix = recordID.uuidString
        let files = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.temporary, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func generateMetadata(recordID: UUID, fileName: String) {
        let fileURL = AppPaths.mediaURL(fileName: fileName)
        let remoteArtwork = library.record(id: recordID)?.thumbnailRemoteURL
        Task.detached(priority: .utility) { [weak self] in
            let thumbnail = await ThumbnailService.makeThumbnail(for: fileURL, recordID: recordID)
            var artwork = thumbnail
            if artwork == nil, let remoteArtwork {
                artwork = await ThumbnailService.saveRemoteImage(from: remoteArtwork, recordID: recordID)
            }
            let duration = await ThumbnailService.duration(of: fileURL)
            await self?.applyMetadata(recordID: recordID, thumbnail: artwork, duration: duration)
        }
    }

    private func applyMetadata(recordID: UUID, thumbnail: String?, duration: Double?) {
        library.update(recordID) { record in
            if let thumbnail { record.thumbnailName = thumbnail }
            if let duration { record.duration = duration }
        }
    }

    private static func media(from record: DownloadRecord) -> ResolvedMedia {
        ResolvedMedia(
            kind: record.kind,
            url: record.remoteURL,
            title: record.title,
            mimeType: record.mimeType,
            contentLength: record.bytesExpected > 0 ? record.bytesExpected : nil,
            thumbnailURL: record.thumbnailRemoteURL,
            pageURL: record.sourceURL,
            httpHeaders: record.httpHeaders ?? [:]
        )
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

        // A task that was already replaced (the media address was re-resolved) must not write
        // over the file the current task is producing.
        guard registry.isCurrent(taskID: downloadTask.taskIdentifier, recordID: entry.recordID) else {
            try? FileManager.default.removeItem(at: location)
            return
        }

        // A download task saves whatever the server sent, including the error page for a
        // rejected signed address. Check the status before treating the file as the video.
        if let status = Self.rejectionStatus(from: downloadTask.response) {
            try? FileManager.default.removeItem(at: location)
            Task { @MainActor [weak self] in
                await self?.handleRejectedResponse(recordID: entry.recordID, status: status)
            }
            return
        }

        let fileName = "\(entry.recordID.uuidString).\(entry.fileExtension)"
        let destination = AppPaths.mediaURL(fileName: fileName)
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            let bytes = (try? FileManager.default.attributesOfItem(
                atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            Task { @MainActor [weak self] in
                self?.finish(recordID: entry.recordID, fileName: fileName, bytes: bytes)
            }
        } catch {
            Task { @MainActor [weak self] in
                #if DEBUG
                NSLog("Save failed: \(error.localizedDescription)")
                #endif
                self?.fail(recordID: entry.recordID,
                           message: L("Couldn't save the file. Please try again.",
                                      "文件保存失败，请重试。"))
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

        // A replaced task's failure says nothing about the transfer that took over, so it must
        // not pause or fail the record — the current task is still running.
        guard registry.isCurrent(taskID: task.taskIdentifier, recordID: entry.recordID) else {
            #if DEBUG
            NSLog("Stale task \(task.taskIdentifier) finished for \(entry.recordID.uuidString.prefix(8)); ignoring")
            #endif
            return
        }

        if let resumeData {
            try? resumeData.write(to: AppPaths.resumeDataURL(recordID: entry.recordID), options: .atomic)
        }

        let rejected = Self.isRejectedAddress(nsError)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The task is gone either way; holding on to it would keep the queue from
            // starting the replacement below.
            self.activeTasks[entry.recordID] = nil
            // A lapsed signed address: re-resolve the page before deciding anything else,
            // because the resume data it came with points at the dead URL too.
            if rejected, await self.recoverFromRejectedURL(recordID: entry.recordID) { return }

            if resumeData != nil {
                self.markPaused(recordID: entry.recordID,
                                message: rejected
                                    ? Self.expiredLinkMessage
                                    : L("Connection lost. Tap resume to continue.",
                                        "连接中断。点继续接着下载。"))
            } else {
                self.fail(recordID: entry.recordID, message: Self.readableMessage(for: nsError))
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
            return L("You appear to be offline. Tap resume when you're back.",
                     "网络好像断开了。恢复网络后点继续。")
        case NSURLErrorTimedOut:
            return L("The server took too long to respond.", "服务器响应超时。")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return L("The server's security certificate couldn't be verified.",
                     "无法验证服务器的安全证书。")
        case NSURLErrorUnsupportedURL:
            return L("That link can't be downloaded directly.", "这个链接无法直接下载。")
        default:
            #if DEBUG
            NSLog("Download failed: \(error.domain) \(error.code) \(error.localizedDescription)")
            #endif
            return L("Download failed. Check your connection and try again.",
                     "下载失败，请检查网络后重试。")
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
    /// The task currently responsible for a record. A transfer can be replaced mid-flight
    /// (a lapsed media address is re-resolved and restarted), and the replaced task's
    /// delegate callbacks still arrive.
    private var current: [UUID: Int] = [:]
    private let lock = NSLock()

    func register(_ entry: Entry, for taskID: Int) {
        lock.lock(); defer { lock.unlock() }
        entries[taskID] = entry
        current[entry.recordID] = taskID
    }

    func entry(for taskID: Int) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[taskID]
    }

    func remove(_ taskID: Int) {
        lock.lock(); defer { lock.unlock() }
        entries[taskID] = nil
        for (recordID, active) in current where active == taskID {
            current[recordID] = nil
        }
    }

    /// `false` when `taskID` was already replaced by a newer task for the same record, in
    /// which case its callbacks must not touch the record or its files. Unknown tasks are
    /// treated as current so a re-delivered session task keeps working.
    func isCurrent(taskID: Int, recordID: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard entries[taskID] != nil else { return true }
        return current[recordID] == taskID
    }
}
