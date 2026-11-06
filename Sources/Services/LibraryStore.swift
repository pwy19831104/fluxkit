import Foundation
import Observation

/// Single source of truth for everything the user has downloaded.
@MainActor
@Observable
final class LibraryStore {

    static let shared = LibraryStore()

    private(set) var records: [DownloadRecord] = []
    /// Set when the index on disk could not be used, so Settings can say so instead of the app
    /// silently looking "empty".
    private(set) var persistenceWarning: String?
    private var canSave = true
    /// Debounce for structural changes, and the floor between two writes while progress callbacks
    /// keep arriving (a download reports several times per second).
    private static let saveDebounce: UInt64 = 400_000_000
    private static let saveInterval: UInt64 = 2_000_000_000

    private var saveTask: Task<Void, Never>?
    private var needsSave = false

    private init() {
        load()
    }

    // MARK: - Queries

    var active: [DownloadRecord] {
        records.filter(\.isActive).sorted { $0.createdAt > $1.createdAt }
    }

    var finished: [DownloadRecord] {
        records.filter { $0.state == .finished }.sorted { $0.createdAt > $1.createdAt }
    }

    var failed: [DownloadRecord] {
        records.filter { $0.state == .failed || $0.state == .cancelled }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var totalBytes: Int64 {
        records.filter { $0.state == .finished }.reduce(0) { $0 + $1.bytesReceived }
    }

    /// Media file names that records point at. Used to tell a real download from a leftover.
    var referencedMediaFileNames: Set<String> {
        Set(records.compactMap { $0.fileName })
    }

    func record(id: UUID) -> DownloadRecord? {
        records.first { $0.id == id }
    }

    func fileURL(for record: DownloadRecord) -> URL? {
        guard let name = record.fileName else { return nil }
        let url = AppPaths.mediaURL(fileName: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailURL(for record: DownloadRecord) -> URL? {
        guard let name = record.thumbnailName else { return nil }
        let url = AppPaths.thumbnailURL(fileName: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Mutations

    func upsert(_ record: DownloadRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        scheduleSave()
    }

    /// Mutates a record in place. Progress updates arrive many times per second, which is why
    /// saving is debounced in `scheduleSave()`.
    func update(_ id: UUID, _ mutate: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutate(&records[index])
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        if let name = record.fileName {
            try? FileManager.default.removeItem(at: AppPaths.mediaURL(fileName: name))
        }
        if let name = record.thumbnailName {
            try? FileManager.default.removeItem(at: AppPaths.thumbnailURL(fileName: name))
        }
        try? FileManager.default.removeItem(at: AppPaths.resumeDataURL(recordID: record.id))
        AppPaths.removeHLSWork(recordID: record.id)
        AppPaths.removeSubtitles(recordID: record.id)
        records.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        let result = PersistedIndex.load(DownloadRecord.self,
                                         from: AppPaths.stateFile,
                                         label: L("library", "片库"))
        records = result.items
        persistenceWarning = result.warning
        canSave = result.canSave
        if let warning = result.warning { NSLog("LibraryStore: \(warning)") }
    }

    /// Coalesces bursts into a single loop: it used to cancel and recreate a `Task` on every
    /// progress callback (several per second) and write the whole index each time.
    private func scheduleSave() {
        needsSave = true
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: Self.saveDebounce)
                guard let self, self.needsSave else { break }
                self.needsSave = false
                self.saveNow()
                // Keep a floor between writes while callbacks keep coming.
                try? await Task.sleep(nanoseconds: Self.saveInterval)
            }
            self?.saveTask = nil
        }
    }

    func saveNow() {
        needsSave = false
        // Never overwrite an index this build could not read (newer schema / unreadable file).
        guard canSave else { return }
        PersistedIndex.save(records, to: AppPaths.stateFile)
    }
}
