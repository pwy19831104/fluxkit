import XCTest
@testable import FluxKit

/// Concurrency stress for `TaskRegistry`.
///
/// The class is `@unchecked Sendable` and protects two dictionaries with an `NSLock`. Sequential
/// unit tests exercise the state machine but cannot catch a missing lock or a read-then-write
/// window. This test hammers the registry from several threads at once; the assertions are
/// deterministic because each worker owns its own record and task IDs. Its main value shows up
/// under ThreadSanitizer (nightly in `.github/workflows/sanitizers.yml`).
///
/// The contract being pinned down (see `TaskRegistry.isCurrent`):
/// - a registered task is current only while it is the newest task for its record;
/// - a replaced task is never current again, so its late callbacks cannot touch the record;
/// - a task the registry has never seen — or one that has been removed — counts as current, so a
///   re-delivered session task after a relaunch is not swallowed;
/// - a registered task with no active mapping for its record is not current.
final class TaskRegistryConcurrencyTests: XCTestCase {

    func testConcurrentRegisterLookupAndRemove() {
        let registry = TaskRegistry()
        let workers = 8
        let iterations = 300

        let finished = expectation(description: "workers finished")
        finished.expectedFulfillmentCount = workers

        for worker in 0..<workers {
            DispatchQueue.global().async {
                let recordID = UUID()
                let entry = TaskRegistry.Entry(recordID: recordID, fileExtension: "mp4")
                let base = worker * 1_000_000

                for index in 0..<iterations {
                    let taskID = base + index * 2
                    let replacement = taskID + 1

                    registry.register(entry, for: taskID)
                    XCTAssertTrue(registry.isCurrent(taskID: taskID, recordID: recordID))
                    XCTAssertEqual(registry.entry(for: taskID)?.recordID, recordID)

                    // A newer task takes over the record; the old one must go stale.
                    registry.register(entry, for: replacement)
                    XCTAssertFalse(
                        registry.isCurrent(taskID: taskID, recordID: recordID),
                        "replaced task \(taskID) must not be current"
                    )
                    XCTAssertTrue(registry.isCurrent(taskID: replacement, recordID: recordID))

                    // A stale task must never look current again, even after the newer one leaves.
                    registry.remove(replacement)
                    XCTAssertNil(registry.entry(for: replacement))
                    XCTAssertFalse(
                        registry.isCurrent(taskID: taskID, recordID: recordID),
                        "stale task \(taskID) must stay non-current after its replacement is removed"
                    )
                    XCTAssertTrue(
                        registry.isCurrent(taskID: replacement, recordID: recordID),
                        "a removed task counts as unknown, which is current by design"
                    )

                    // Bound the dictionaries: drop the record's task every 25 iterations.
                    if index % 25 == 0 { registry.remove(taskID) }
                }

                finished.fulfill()
            }
        }

        wait(for: [finished], timeout: 120)
    }

    /// A task that was never registered is current: after a relaunch the background session can
    /// deliver callbacks before the registry is rebuilt.
    func testUnknownTaskIsTreatedAsCurrentUnderLoad() {
        let registry = TaskRegistry()
        let workers = 4
        let finished = expectation(description: "workers finished")
        finished.expectedFulfillmentCount = workers

        for worker in 0..<workers {
            DispatchQueue.global().async {
                let recordID = UUID()
                let entry = TaskRegistry.Entry(recordID: recordID, fileExtension: "mp4")
                for index in 0..<200 {
                    registry.register(entry, for: worker * 1_000 + index)
                    XCTAssertTrue(
                        registry.isCurrent(taskID: 900_000 + index, recordID: UUID()),
                        "a task the registry never saw must count as current"
                    )
                }
                finished.fulfill()
            }
        }

        wait(for: [finished], timeout: 120)
    }
}
