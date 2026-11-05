import Foundation

/// A simple in-memory play queue: the list you opened plus the item you tapped.
struct PlaybackQueue: Equatable {
    private(set) var items: [DownloadRecord]
    private(set) var index: Int

    init?(items: [DownloadRecord], startingAt recordID: UUID) {
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == recordID }) else { return nil }
        self.items = items
        self.index = index
    }

    var current: DownloadRecord? {
        items.indices.contains(index) ? items[index] : nil
    }

    var hasNext: Bool { index + 1 < items.count }
    var hasPrevious: Bool { index > 0 }
    var count: Int { items.count }

    var positionText: String? {
        guard items.count > 1 else { return nil }
        return L("\(index + 1) of \(items.count)", "\(index + 1) / \(items.count)")
    }

    @discardableResult
    mutating func advance() -> DownloadRecord? {
        guard hasNext else { return nil }
        index += 1
        return items[index]
    }

    @discardableResult
    mutating func rewind() -> DownloadRecord? {
        guard hasPrevious else { return nil }
        index -= 1
        return items[index]
    }

    /// Skips an item that was removed from the library.
    mutating func removeCurrent() {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if index >= items.count { index = max(0, items.count - 1) }
    }
}
