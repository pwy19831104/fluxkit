import XCTest
@testable import FluxKit

@MainActor
final class ImportServiceTests: XCTestCase {

    func testImportsFileIntoLibrary() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluxKit-Import-\(UUID().uuidString).mp4")
        let payload = Data(repeating: 7, count: 4096)
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: payload))

        let record = try await ImportService.importFile(from: source, library: LibraryStore.shared)
        defer {
            LibraryStore.shared.remove(record.id)
            try? FileManager.default.removeItem(at: source)
        }

        XCTAssertEqual(record.state, .finished)
        XCTAssertEqual(record.bytesReceived, Int64(payload.count))
        let fileName = try XCTUnwrap(record.fileName)
        XCTAssertTrue(fileName.hasSuffix(".mp4"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: AppPaths.mediaURL(fileName: fileName).path
        ))
        XCTAssertTrue(record.title.contains("FluxKit-Import"))
    }

    func testRejectsUnsupportedExtension() async {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluxKit-\(UUID().uuidString).txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data("nope".utf8)))
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await ImportService.importFile(from: source, library: LibraryStore.shared)
            XCTFail("Expected unsupported error")
        } catch {
            XCTAssertTrue(error is ImportError)
        }
    }

    func testFileNamesAreSanitizedAndUnique() {
        XCTAssertEqual(FileNames.sanitize("A/B: C?"), "A B C")
        XCTAssertFalse(FileNames.sanitize("   ").isEmpty)

        // APFS caps names at 255 bytes; 70 emoji would be 280, so the limit is on bytes.
        let emoji = FileNames.sanitize(String(repeating: "🎬", count: 70))
        XCTAssertLessThanOrEqual(emoji.utf8.count, 200, "name must stay well under the 255-byte limit")
        XCTAssertFalse(emoji.isEmpty)

        // A leading dot would hide the file in Files.app.
        XCTAssertEqual(FileNames.sanitize(".hidden clip"), "hidden clip")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = FileNames.uniqueName(title: "Clip", extension: "mp4", in: dir)
        XCTAssertTrue(FileManager.default.createFile(atPath: dir.appendingPathComponent(first).path, contents: Data()))
        let second = FileNames.uniqueName(title: "Clip", extension: "mp4", in: dir)
        XCTAssertNotEqual(first, second)
    }
}
