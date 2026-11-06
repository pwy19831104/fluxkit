import XCTest
@testable import FluxKit

/// Covers the leak found by the smoke run: pause/resume left the first attempt's file behind while
/// the record pointed at `Title (2).mp4` (see `docs/SMOKE_REPORT.md`, P2).
final class MediaSweepTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func file(_ name: String, age: TimeInterval, bytes: Int64 = 1_000) -> (name: String, modified: Date, bytes: Int64) {
        (name, ago(age), bytes)
    }

    func testUnreferencedOldMediaIsReclaimed() {
        let files = [
            file("Clip.mp4", age: 72 * 3600),
            file("Clip (2).mp4", age: 72 * 3600),
        ]
        let candidates = MediaSweep.candidates(
            files: files,
            referenced: ["Clip (2).mp4"],
            now: now
        )
        XCTAssertEqual(candidates.map(\.name), ["Clip.mp4"])
    }

    func testRecentFilesAreKept() {
        // A download that finished minutes ago is not an orphan — it may still be being adopted.
        let files = [file("JustFinished.mp4", age: 60)]
        XCTAssertTrue(MediaSweep.candidates(files: files, referenced: [], now: now).isEmpty)
    }

    func testSubtitleSidecarsAreNeverDeleted() {
        let files = [
            file("Clip.mp4", age: 72 * 3600),
            file("Clip.en.vtt", age: 72 * 3600),
            file("Clip.srt", age: 72 * 3600),
            file("Clip.ass", age: 72 * 3600),
        ]
        let candidates = MediaSweep.candidates(files: files, referenced: [], now: now)
        XCTAssertEqual(candidates.map(\.name), ["Clip.mp4"])
    }

    func testUUIDNamesAreTreatedAsIntermediates() {
        // Progressive/HLS scratch output lives under the record UUID; deleting it mid-download
        // would break the job.
        let uuid = UUID().uuidString
        let files = [file("\(uuid).mp4", age: 72 * 3600)]
        XCTAssertTrue(MediaSweep.candidates(files: files, referenced: [], now: now).isEmpty)
    }

    func testSweepDeletesOnlyOrphansOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaSweepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let orphan = directory.appendingPathComponent("Orphan.mp4")
        let kept = directory.appendingPathComponent("Kept.mp4")
        try Data(repeating: 0, count: 2_048).write(to: orphan)
        try Data(repeating: 0, count: 1_024).write(to: kept)

        // Age both files past the threshold.
        let old = now.addingTimeInterval(-72 * 3600)
        for url in [orphan, kept] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }

        let freed = MediaSweep.sweep(
            in: directory,
            referenced: ["Kept.mp4"],
            minimumAge: 24 * 3600,
            now: now
        )

        XCTAssertEqual(freed, 2_048)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }
}

/// The naming half of the fix: adopting a finished download must reclaim a leftover same-title file
/// instead of producing `Title (2).mp4` and leaving the first copy orphaned.
final class FileNamesAdoptTests: XCTestCase {

    func testReusesLeftoverNameWhenNothingReferencesIt() throws {
        let directory = AppPaths.downloads
        let leftover = directory.appendingPathComponent("AdoptTest.mp4")
        let incoming = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data([0x00]).write(to: leftover)
        try Data([0x01, 0x02]).write(to: incoming)
        defer {
            try? FileManager.default.removeItem(at: leftover)
            try? FileManager.default.removeItem(at: incoming)
        }

        let adopted = FileNames.adopt(
            fileName: incoming.lastPathComponent,
            title: "AdoptTest",
            referenced: [],
            recordID: UUID()
        )

        XCTAssertEqual(adopted, "AdoptTest.mp4", "a leftover name should be reclaimed, not suffixed")
        let size = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(adopted).path
        )[.size] as? NSNumber
        XCTAssertEqual(size?.intValue, 2, "the new file must replace the leftover")
    }

    func testSuffixesWhenTheNameBelongsToAnotherRecord() throws {
        let directory = AppPaths.downloads
        let owned = directory.appendingPathComponent("AdoptOwned.mp4")
        let incoming = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data([0x00]).write(to: owned)
        try Data([0x01]).write(to: incoming)
        defer {
            try? FileManager.default.removeItem(at: owned)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("AdoptOwned (2).mp4"))
            try? FileManager.default.removeItem(at: incoming)
        }

        let adopted = FileNames.adopt(
            fileName: incoming.lastPathComponent,
            title: "AdoptOwned",
            referenced: ["AdoptOwned.mp4"],
            recordID: UUID()
        )

        XCTAssertEqual(adopted, "AdoptOwned (2).mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path), "the referenced file must survive")
    }
}
