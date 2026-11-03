import Foundation

// MARK: - Public types

enum MediaKind: String, Codable, Sendable {
    case progressive   // single file: mp4 / mov / webm ...
    case hls           // m3u8 playlist
}

struct ResolvedMedia: Identifiable, Sendable {
    let id = UUID()
    var kind: MediaKind
    /// The address that will actually be downloaded.
    var url: URL
    /// Human readable name, from og:title / <title> / URL last path component.
    var title: String?
    var mimeType: String?
    var contentLength: Int64?
    var thumbnailURL: URL?
    var pageURL: URL?
    var httpHeaders: [String: String] = [:]

    var fileExtension: String {
        switch kind {
        case .hls:
            return "mp4"
        case .progressive:
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty, ext.count <= 5, Self.mediaExtensions.contains(ext) {
                return ext
            }
            if let mime = mimeType?.lowercased() {
                if mime.contains("quicktime") { return "mov" }
                if mime.contains("webm") { return "webm" }
                if mime.contains("matroska") { return "mkv" }
                if mime.contains("mp4") || mime.contains("m4v") { return "mp4" }
            }
            return "mp4"
        }
    }

    var host: String { pageURL?.host ?? url.host ?? url.absoluteString }

    /// A name that is pleasant in a list: page titles first, then the file name,
    /// then something host-based for generic playlist URLs like `master.m3u8`.
    var suggestedTitle: String {
        if let title, !title.trimmed.isEmpty { return title.trimmed }
        let last = url.deletingPathExtension().lastPathComponent
        let humanized = last
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmed
        let generic: Set<String> = ["master", "index", "playlist", "hls", "m3u8", "stream",
                                    "manifest", "video", "main", "prog_index", "chunklist"]
        if !humanized.isEmpty, !generic.contains(last.lowercased()) { return humanized }
        if let host = url.host {
            return "Video from " + host.replacingOccurrences(of: "www.", with: "")
        }
        return "Video"
    }

    static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "flv", "3gp",
        "mp3", "m4a", "aac", "wav", "ogg", "opus"
    ]
}

enum ResolveError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case noMediaFound
    case protectedStream(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste a link first."
        case .invalidURL:
            return "That doesn't look like a valid link."
        case .noMediaFound:
            return "No downloadable video was found on that page. Try a direct link to an MP4 or an .m3u8 stream."
        case .protectedStream(let reason):
            return reason
        case .network(let reason):
            return "Network error: \(reason)"
        }
    }
}

// MARK: - Persisted download record

enum DownloadState: String, Codable, Sendable {
    case queued
    case running
    case paused
    case finished
    case failed
    case cancelled
}

struct DownloadRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var sourceURL: URL
    var remoteURL: URL
    var kind: MediaKind
    var state: DownloadState
    var bytesReceived: Int64
    var bytesExpected: Int64
    /// File name inside the downloads directory.
    var fileName: String?
    var thumbnailName: String?
    var createdAt: Date
    var duration: Double?
    var errorMessage: String?

    init(media: ResolvedMedia) {
        self.id = UUID()
        self.title = media.suggestedTitle
        self.sourceURL = media.pageURL ?? media.url
        self.remoteURL = media.url
        self.kind = media.kind
        self.state = .queued
        self.bytesReceived = 0
        self.bytesExpected = media.contentLength ?? 0
        self.createdAt = Date()
    }

    var progress: Double {
        guard state != .finished else { return 1 }
        guard bytesExpected > 0 else { return 0 }
        return min(max(Double(bytesReceived) / Double(bytesExpected), 0), 1)
    }

    var isActive: Bool {
        state == .running || state == .queued || state == .paused
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
