import XCTest
@testable import FluxKit

@MainActor
final class AppPathsMigrationTests: XCTestCase {

    func testLegacyMediaMovesToDocuments() throws {
        let legacy = AppPaths.root.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let name = "legacy-\(UUID().uuidString).mp4"
        let source = legacy.appendingPathComponent(name)
        try Data("legacy".utf8).write(to: source)

        AppPaths.migrateMediaIfNeeded()

        let destination = AppPaths.downloads.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        try? FileManager.default.removeItem(at: destination)
    }

    func testResumeDataLivesOutsideMediaFolder() {
        let recordID = UUID()
        let url = AppPaths.resumeDataURL(recordID: recordID)
        XCTAssertEqual(url.lastPathComponent, "\(recordID.uuidString).resume")
        XCTAssertTrue(url.path.contains("Resume"))
        XCTAssertFalse(url.path.contains("/Media/"))
    }
}
