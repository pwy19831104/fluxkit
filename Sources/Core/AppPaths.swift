import Foundation

/// All on-disk locations used by the app. Everything lives in Application Support so
/// that Files.app / iTunes sharing (Documents) can expose only user-facing media.
enum AppPaths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("DownloadKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    static let downloads: URL = {
        let url = root.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

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

    static func mediaURL(fileName: String) -> URL { downloads.appendingPathComponent(fileName) }
    static func resumeDataURL(recordID: UUID) -> URL { downloads.appendingPathComponent("\(recordID.uuidString).resume") }
    static func thumbnailURL(fileName: String) -> URL { thumbnails.appendingPathComponent(fileName) }
}
