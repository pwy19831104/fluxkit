#if DEBUG
import Foundation

/// Development-only fixtures for screenshots and UI tests.
/// Launch with `-seedLibrary` to replace the library with deterministic items.
enum DebugSeed {
    @MainActor
    static func seedIfRequested(library: LibraryStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedLibrary") else { return }
        for record in library.records {
            library.remove(record.id)
        }

        let titles = ["Alpha Clip", "Bravo Clip", "Charlie Clip"]
        for (index, title) in titles.enumerated() {
            let url = URL(string: "https://example.com/demo-\(index).mp4")!
            var record = DownloadRecord(
                media: ResolvedMedia(kind: .progressive, url: url, title: title)
            )
            record.state = .finished
            record.bytesReceived = Int64(1_000_000 * (index + 1))
            record.bytesExpected = record.bytesReceived
            record.duration = 60
            record.createdAt = Date().addingTimeInterval(-Double(index) * 3600)
            if index == 1 {
                record.lastPosition = 30 // resume at 50%
            } else if index == 2 {
                record.played = true   // finished badge
                record.lastPosition = nil
            }
            library.upsert(record)
        }
    }
}
#endif
