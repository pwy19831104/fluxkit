import Foundation

/// Pure query helpers for the library list.
///
/// The filtering and sorting rules used to live inline in `LibraryView`, which meant they could
/// only be checked by eye. Keeping them here makes them unit-testable and lets the performance
/// tests in `PerformanceTests` measure the real implementation instead of a copy.
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case largest
    case title

    var id: String { rawValue }
}

enum LibraryQuery {

    /// Case-insensitive title match. An empty or whitespace-only query matches everything.
    static func filter(_ records: [DownloadRecord], query: String) -> [DownloadRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return records }
        return records.filter { $0.title.lowercased().contains(needle) }
    }

    static func sorted(_ records: [DownloadRecord], by sort: LibrarySort) -> [DownloadRecord] {
        switch sort {
        case .newest:
            return records.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return records.sorted { $0.createdAt < $1.createdAt }
        case .largest:
            return records.sorted { $0.bytesReceived > $1.bytesReceived }
        case .title:
            return records.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    static func apply(
        _ records: [DownloadRecord],
        query: String,
        sort: LibrarySort
    ) -> [DownloadRecord] {
        sorted(filter(records, query: query), by: sort)
    }
}
