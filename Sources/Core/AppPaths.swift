import Foundation

/// All on-disk locations used by the app. Everything lives in Application Support so
/// that Files.app / iTunes sharing (Documents) can expose only user-facing media.
enum AppPaths {
    /// Folder name used before the FluxKit rename; adopted once so existing downloads survive.
    private static let legacyContainerName = "StreamKit"

    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("FluxKit", isDirectory: true)
        adoptLegacyContainer(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Downloaded media can be gigabytes; never let it eat the user's iCloud backup quota.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        return root
    }()

    /// Media lives in Documents so the Files app can browse it ("On My iPhone → FluxKit").
    /// Everything else (index, thumbnails, resume data) stays in Application Support.
    static let downloads: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let container = base.appendingPathComponent("FluxKit", isDirectory: true)
        adoptLegacyContainer(at: container)
        let url = container
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        return url
    }()

    /// One-time `StreamKit` → `FluxKit` container rename so media and `library.json` survive the
    /// project rename. Never touches an existing FluxKit container.
    private static func adoptLegacyContainer(at destination: URL) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { return }
        let legacy = destination.deletingLastPathComponent()
            .appendingPathComponent(legacyContainerName, isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return }
        try? manager.moveItem(at: legacy, to: destination)
    }

    /// Moves media from the old Application Support location (pre Files-app support).
    static func migrateMediaIfNeeded() {
        let fileManager = FileManager.default
        let legacy = root.appendingPathComponent("Media", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        try? fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)

        let files = (try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            if file.pathExtension == "resume" {
                try? fileManager.removeItem(at: file)
                continue
            }
            let destination = downloads.appendingPathComponent(file.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: file, to: destination)
        }
        try? fileManager.removeItem(at: legacy)
    }

    static let thumbnails: URL = {
        let url = root.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let temporary: URL = {
        let url = root.appendingPathComponent("Temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var stateFile: URL { root.appendingPathComponent("library.json") }

    /// Deletes leftovers of HLS jobs that were killed mid-flight (the stitcher writes
    /// concatenated segment files into `temporary`). Safe at launch: no HLS job is running yet,
    /// and progressive transfers live in the system's own temp directory.
    static func purgeTemporaryFiles() {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? manager.removeItem(at: file)
        }
    }

    static func mediaURL(fileName: String) -> URL { downloads.appendingPathComponent(fileName) }

    // MARK: - HLS scratch space

    static let hlsWorkRoot: URL = {
        let url = root.appendingPathComponent("HLSWork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Segments downloaded so far live here so a paused/interrupted HLS job can resume.
    static func hlsWork(recordID: UUID) -> URL {
        let url = hlsWorkRoot.appendingPathComponent("hls-\(recordID.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func hlsHasProgress(recordID: UUID) -> Bool {
        let dir = hlsWork(recordID: recordID)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return files.contains { $0.hasSuffix(".seg") }
    }

    static func removeHLSWork(recordID: UUID) {
        try? FileManager.default.removeItem(at: hlsWork(recordID: recordID))
    }
    static func resumeDataURL(recordID: UUID) -> URL {
        let url = root.appendingPathComponent("Resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.appendingPathComponent("\(recordID.uuidString).resume")
    }
    static func thumbnailURL(fileName: String) -> URL { thumbnails.appendingPathComponent(fileName) }

    // MARK: - Subtitles

    static func subtitleURL(recordID: UUID, language: String) -> URL {
        downloads.appendingPathComponent("\(recordID.uuidString).\(sanitize(language)).vtt")
    }

    /// Sidecar subtitles saved next to a download, newest first.
    static func subtitleFiles(recordID: UUID) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(recordID.uuidString) && $0.pathExtension == "vtt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func removeSubtitles(recordID: UUID) {
        for file in subtitleFiles(recordID: recordID) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func sanitize(_ language: String) -> String {
        let allowed = language.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let value = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "und" : value
    }
}
