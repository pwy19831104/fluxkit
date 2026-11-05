import Foundation
import Observation

/// Single source of truth for everything the user has downloaded.
@MainActor
@Observable
final class LibraryStore {

    static let shared = LibraryStore()

    private(set) var records: [DownloadRecord] = []
    private var saveTask: Task<Void, Never>?

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

    /// Mutates a record in place. Progress updates arrive many times per second, so the
    /// caller may pass `persist: false` and rely on the debounced save.
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
        guard let data = try? Data(contentsOf: AppPaths.stateFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([DownloadRecord].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = records
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: AppPaths.stateFile, options: .atomic)
    }
}
