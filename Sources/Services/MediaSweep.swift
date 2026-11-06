import Foundation

/// Reclaims media files that no library record points at.
///
/// Smoke testing found the leak this exists for: pausing and resuming a download could leave the
/// first attempt's file behind under the plain title while the record pointed at `Title (2).mp4`.
/// Nothing ever deleted the first file, so every such cycle cost a full copy of the media.
///
/// Two guards keep this safe:
/// - only files older than `minimumAge` are considered, so an in-flight download's scratch files
///   (which are written under their UUID name) are never touched;
/// - UUID-named files and subtitle sidecars are skipped outright, because those are intermediates
///   and companions rather than library entries.
enum MediaSweep {

    static let protectedExtensions: Set<String> = ["vtt", "srt", "ass"]

    struct Candidate: Equatable {
        var name: String
        var bytes: Int64
    }

    /// Pure decision function, separated so it can be unit-tested without touching the disk.
    static func candidates(
        in directory: URL,
        referenced: Set<String>,
        minimumAge: TimeInterval = 24 * 3600,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [Candidate] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var found: [(String, Date, Int64)] = []

        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber else { continue }
            found.append((name, modified, size.int64Value))
        }

        return candidates(
            files: found,
            referenced: referenced,
            minimumAge: minimumAge,
            now: now
        )
    }

    static func candidates(
        files: [(name: String, modified: Date, bytes: Int64)],
        referenced: Set<String>,
        minimumAge: TimeInterval = 24 * 3600,
        now: Date = Date()
    ) -> [Candidate] {
        files.compactMap { file in
            guard !referenced.contains(file.name) else { return nil }
            guard !protectedExtensions.contains((file.name as NSString).pathExtension.lowercased())
            else { return nil }
            // UUID names are download intermediates (and HLS scratch output), never library entries.
            let base = (file.name as NSString).deletingPathExtension
            if UUID(uuidString: base) != nil { return nil }
            guard now.timeIntervalSince(file.modified) > minimumAge else { return nil }
            return Candidate(name: file.name, bytes: file.bytes)
        }
    }

    /// Deletes the candidates and returns the freed bytes. Best effort: a file that disappears
    /// between the scan and the delete is not an error.
    @discardableResult
    static func sweep(
        in directory: URL,
        referenced: Set<String>,
        minimumAge: TimeInterval = 24 * 3600,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Int64 {
        var freed: Int64 = 0
        for candidate in candidates(
            in: directory,
            referenced: referenced,
            minimumAge: minimumAge,
            now: now,
            fileManager: fileManager
        ) {
            let url = directory.appendingPathComponent(candidate.name)
            if (try? fileManager.removeItem(at: url)) != nil {
                freed += candidate.bytes
            }
        }
        return freed
    }
}
