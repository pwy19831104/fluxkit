import XCTest
@testable import FluxKit

/// `LinkInbox` is the App Group hand-off used by the share extension. It replaced a
/// `UserDefaults` read-modify-write, which silently dropped links when the extension pushed while
/// the app popped (THR-05 in `docs/TEST_PLAN.md`).
final class LinkInboxTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeInbox() -> LinkInbox { LinkInbox(directory: directory) }

    func testPushThenPopReturnsTheLink() {
        let inbox = makeInbox()
        XCTAssertTrue(inbox.push("https://example.com/a.mp4"))
        XCTAssertEqual(inbox.count, 1)
        XCTAssertEqual(inbox.popNewest(), "https://example.com/a.mp4")
        XCTAssertEqual(inbox.count, 0)
        XCTAssertNil(inbox.popNewest())
    }

    func testPopReturnsNewestFirst() {
        let inbox = makeInbox()
        for index in 0..<5 {
            XCTAssertTrue(inbox.push("https://example.com/\(index).mp4"))
        }
        XCTAssertEqual(inbox.count, 5)

        // Newest first, so the same order the app would hand to the input field.
        XCTAssertEqual(inbox.popNewest(), "https://example.com/4.mp4")
        XCTAssertEqual(inbox.popNewest(), "https://example.com/3.mp4")
        XCTAssertEqual(inbox.count, 3)
    }

    func testConsecutiveDuplicateIsIgnored() {
        let inbox = makeInbox()
        XCTAssertTrue(inbox.push("https://example.com/same.mp4"))
        XCTAssertFalse(inbox.push("https://example.com/same.mp4"))
        XCTAssertEqual(inbox.count, 1)
    }

    func testEmptyAndWhitespaceAreRejected() {
        let inbox = makeInbox()
        XCTAssertFalse(inbox.push("   \n "))
        XCTAssertFalse(inbox.push(""))
        XCTAssertEqual(inbox.count, 0)
    }

    func testTrimsWhitespaceAroundTheLink() {
        let inbox = makeInbox()
        XCTAssertTrue(inbox.push("  https://example.com/trim.mp4 \n"))
        XCTAssertEqual(inbox.popNewest(), "https://example.com/trim.mp4")
    }

    func testOlderLinksBeyondTheLimitAreDropped() {
        let inbox = makeInbox()
        for index in 0..<(LinkInbox.limit + 5) {
            XCTAssertTrue(inbox.push("https://example.com/\(index).mp4"))
        }
        XCTAssertEqual(inbox.count, LinkInbox.limit)

        // The five oldest must be gone, the newest still there.
        let pending = inbox.pendingLinks()
        XCTAssertEqual(pending.first, "https://example.com/5.mp4")
        XCTAssertEqual(pending.last, "https://example.com/\(LinkInbox.limit + 4).mp4")
    }

    /// The old implementation lost entries here: concurrent read-modify-write on one array.
    func testConcurrentPushesKeepEveryDistinctLink() {
        let inbox = makeInbox()
        let workers = 6
        let perWorker = 20

        let done = expectation(description: "pushes finished")
        done.expectedFulfillmentCount = workers

        for worker in 0..<workers {
            DispatchQueue.global().async {
                for index in 0..<perWorker {
                    inbox.push("https://example.com/w\(worker)-\(index).mp4")
                }
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 60)

        let pending = inbox.pendingLinks()
        XCTAssertLessThanOrEqual(pending.count, LinkInbox.limit)
        XCTAssertEqual(Set(pending).count, pending.count, "duplicates mean a lost/clobbered write")
        XCTAssertFalse(pending.isEmpty)
    }

    /// A consumer popping while producers push must never hand out a link that was never written,
    /// and must not crash. Nothing is asserted about exact counts — the point is the absence of
    /// corruption, verified under ThreadSanitizer in CI.
    func testConcurrentPushAndPopStaysConsistent() {
        let inbox = makeInbox()
        let producers = 4
        let consumerIterations = 200

        let done = expectation(description: "workers finished")
        done.expectedFulfillmentCount = producers + 1

        for worker in 0..<producers {
            DispatchQueue.global().async {
                for index in 0..<60 {
                    inbox.push("https://example.com/p\(worker)-\(index).mp4")
                }
                done.fulfill()
            }
        }

        DispatchQueue.global().async {
            for _ in 0..<consumerIterations {
                if let link = inbox.popNewest() {
                    XCTAssertTrue(link.hasPrefix("https://example.com/"), "corrupted payload: \(link)")
                }
                _ = inbox.count
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 60)

        // Everything left must still be readable and well-formed.
        for link in inbox.pendingLinks() {
            XCTAssertTrue(link.hasPrefix("https://example.com/"), "corrupted payload: \(link)")
        }
    }

    func testMigratesLegacyUserDefaultsLinks() {
        let inbox = makeInbox()
        inbox.migrate(legacyLinks: ["https://example.com/old1.mp4", "https://example.com/old2.mp4"])
        XCTAssertEqual(inbox.count, 2)
        XCTAssertEqual(inbox.popNewest(), "https://example.com/old2.mp4")
        XCTAssertEqual(inbox.popNewest(), "https://example.com/old1.mp4")
    }

    func testMigrationIgnoresEmptyInput() {
        let inbox = makeInbox()
        inbox.migrate(legacyLinks: nil)
        inbox.migrate(legacyLinks: [])
        XCTAssertEqual(inbox.count, 0)
    }
}
