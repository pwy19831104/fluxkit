import XCTest
@testable import FluxKit

final class PlaybackQueueTests: XCTestCase {

    private func makeRecords(_ count: Int) -> [DownloadRecord] {
        (0..<count).map { index in
            var record = DownloadRecord(
                media: ResolvedMedia(
                    kind: .progressive,
                    url: URL(string: "https://example.com/\(index).mp4")!,
                    title: "Item \(index)"
                )
            )
            record.state = .finished
            record.duration = 100
            return record
        }
    }

    func testQueueStartsAtTappedItem() throws {
        let items = makeRecords(4)
        let queue = try XCTUnwrap(PlaybackQueue(items: items, startingAt: items[2].id))
        XCTAssertEqual(queue.index, 2)
        XCTAssertEqual(queue.current?.id, items[2].id)
        XCTAssertTrue(queue.hasPrevious)
        XCTAssertTrue(queue.hasNext)
        XCTAssertNotNil(queue.positionText)
    }

    func testAdvanceAndRewindStopAtBounds() throws {
        let items = makeRecords(3)
        var queue = try XCTUnwrap(PlaybackQueue(items: items, startingAt: items[0].id))
        XCTAssertFalse(queue.hasPrevious)
        XCTAssertNil(queue.rewind())

        XCTAssertEqual(queue.advance()?.id, items[1].id)
        XCTAssertEqual(queue.advance()?.id, items[2].id)
        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.index, 2)
    }

    func testRemovingCurrentKeepsIndexValid() throws {
        let items = makeRecords(2)
        var queue = try XCTUnwrap(PlaybackQueue(items: items, startingAt: items[1].id))
        queue.removeCurrent()
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.current?.id, items[0].id)
        queue.removeCurrent()
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.current)
    }

    func testProgressAndPlayedFlags() {
        var record = makeRecords(1)[0]
        XCTAssertEqual(record.playbackProgress, 0)

        record.lastPosition = 25
        XCTAssertEqual(record.playbackProgress, 0.25, accuracy: 0.001)
        XCTAssertFalse(record.isPlayed)

        record.lastPosition = 99
        XCTAssertEqual(record.playbackProgress, 0.99, accuracy: 0.001)

        record.played = true
        record.lastPosition = nil
        XCTAssertEqual(record.playbackProgress, 1)
        XCTAssertTrue(record.isPlayed)
    }
}
