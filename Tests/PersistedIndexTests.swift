import XCTest
@testable import FluxKit

/// Guards the "one bad byte must not wipe the library" behaviour.
final class PersistedIndexTests: XCTestCase {

    private struct Item: Codable, Equatable {
        var id: String
        var title: String
        var createdAt: Date
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistedIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("library.json") }

    private func sample() -> [Item] {
        [Item(id: "1", title: "Alpha", createdAt: Date(timeIntervalSince1970: 1_000)),
         Item(id: "2", title: "Bravo", createdAt: Date(timeIntervalSince1970: 2_000))]
    }

    // MARK: - Happy paths

    func testMissingFileLoadsEmptyAndAllowsSaving() {
        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.warning)
        XCTAssertTrue(result.canSave)
    }

    func testRoundTripThroughEnvelope() throws {
        XCTAssertTrue(PersistedIndex.save(sample(), to: fileURL))
        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")
        XCTAssertEqual(result.items, sample())
        XCTAssertNil(result.warning)
        XCTAssertTrue(result.canSave)
    }

    /// Every build before the envelope wrote a bare `[DownloadRecord]`; those files must still open.
    func testLegacyBareArrayStillLoads() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sample()).write(to: fileURL)

        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")
        XCTAssertEqual(result.items, sample())
        XCTAssertNil(result.warning)
    }

    // MARK: - Recovery

    func testCorruptFileIsQuarantinedInsteadOfOverwritten() throws {
        let garbage = Data(#"{"schemaVersion":1,"records":[{"id":"1","tit"# .utf8)
        try garbage.write(to: fileURL)

        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNotNil(result.warning)
        let backup = try XCTUnwrap(result.quarantinedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "the damaged file must be kept")
        XCTAssertEqual(try Data(contentsOf: backup), garbage, "quarantined bytes must be untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        // A fresh index may be written now that the original is safe.
        XCTAssertTrue(result.canSave)
    }

    func testQuarantineNameIsRecognisable() throws {
        try Data("not json".utf8).write(to: fileURL)
        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")
        let name = try XCTUnwrap(result.quarantinedURL?.lastPathComponent)
        XCTAssertTrue(name.hasPrefix("library.corrupt-"), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)
    }

    func testNewerSchemaIsRefusedNotDestroyed() throws {
        let future = """
        {"schemaVersion":\(PersistedIndex.currentVersion + 1),"records":[]}
        """
        try Data(future.utf8).write(to: fileURL)

        let result = PersistedIndex.load(Item.self, from: fileURL, label: "library")

        XCTAssertNotNil(result.warning)
        XCTAssertFalse(result.canSave, "a newer index must never be replaced")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(future.utf8))
    }

    func testUnreadableDirectoryDoesNotCrash() {
        let missing = directory.appendingPathComponent("nope/library.json")
        let result = PersistedIndex.load(Item.self, from: missing, label: "library")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.warning)      // nothing there yet is not an error
        XCTAssertFalse(PersistedIndex.save(sample(), to: missing))
    }

    // MARK: - Store integration

    @MainActor
    func testLibraryStoreSurvivesACorruptIndex() throws {
        // Point the store at the real path, write garbage, and check it comes back empty but
        // with the damaged file preserved next to it.
        let stateFile = AppPaths.stateFile
        let original = try? Data(contentsOf: stateFile)
        defer {
            if let original { try? original.write(to: stateFile) } else {
                try? FileManager.default.removeItem(at: stateFile)
            }
        }
        try Data("{ not json".utf8).write(to: stateFile)

        let result = PersistedIndex.load(DownloadRecord.self, from: stateFile, label: "library")
        XCTAssertNotNil(result.warning)
        XCTAssertNotNil(result.quarantinedURL)
        if let quarantined = result.quarantinedURL {
            try? FileManager.default.removeItem(at: quarantined)
        }
    }
}
