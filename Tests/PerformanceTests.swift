import XCTest
@testable import FluxKit

/// Performance baselines for the hot paths that run while the user is looking at the screen.
///
/// Thresholds live in `docs/TEST_PLAN.md` (PERF-02, PERF-06). `measure` records the values so a
/// regression shows up as a jump in the test log even before it crosses a hard threshold.
final class PerformanceTests: XCTestCase {

    private func makeRecords(_ count: Int) -> [DownloadRecord] {
        (0..<count).map { index in
            var record = DownloadRecord(
                media: ResolvedMedia(
                    kind: .progressive,
                    url: URL(string: "https://example.com/clip-\(index).mp4")!,
                    title: "Clip \(index) — sample download \(index)"
                )
            )
            record.state = .finished
            record.bytesReceived = Int64((index + 1) * 1_000_000)
            record.bytesExpected = record.bytesReceived
            record.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
            return record
        }
    }

    // MARK: - PERF-02: library search over a large library

    func testSearch500Items() {
        let records = makeRecords(500)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let result = LibraryQuery.filter(records, query: "clip 42")
            XCTAssertFalse(result.isEmpty)
        }
    }

    func testSearchMissDoesNotDegrade() {
        let records = makeRecords(500)
        measure(metrics: [XCTClockMetric()]) {
            XCTAssertTrue(LibraryQuery.filter(records, query: "no-such-title").isEmpty)
        }
    }

    func testFilterAndSort500Items() {
        let records = makeRecords(500)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let result = LibraryQuery.apply(records, query: "clip", sort: .title)
            XCTAssertEqual(result.count, 500)
        }
    }

    // MARK: - PERF-06: index persistence

    func testIndexSaveAndLoad500Records() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-library-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let records = makeRecords(500)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertTrue(PersistedIndex.save(records, to: url), "save failed")
            let loaded = PersistedIndex.load(DownloadRecord.self, from: url, label: "perf")
            XCTAssertEqual(loaded.items.count, 500)
            XCTAssertNil(loaded.warning)
        }
    }
}
