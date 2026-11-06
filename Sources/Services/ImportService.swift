import AVFoundation
import Foundation

enum ImportError: LocalizedError {
    case unsupported
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return L("That file type can't be imported. Use a video or audio file.",
                     "无法导入这种文件。请选择视频或音频文件。")
        case .copyFailed(let reason):
            return L("Couldn't import the file: \(reason)", "导入失败：\(reason)")
        }
    }
}

/// Copies files picked in Files.app into the FluxKit library.
enum ImportService {

    static let allowedExtensions: Set<String> = ResolvedMedia.mediaExtensions

    @MainActor
    static func importFile(from source: URL, library: LibraryStore) async throws -> DownloadRecord {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { throw ImportError.unsupported }

        let title = source.deletingPathExtension().lastPathComponent
        let recordID = UUID()
        let fileName = FileNames.uniqueName(
            title: title,
            extension: ext,
            in: AppPaths.downloads
        )
        let destination = AppPaths.mediaURL(fileName: fileName)

        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        var record = DownloadRecord(
            media: ResolvedMedia(kind: .progressive, url: source, title: title)
        )
        record.state = .finished
        record.isImported = true
        record.fileName = fileName
        record.bytesReceived = bytes
        record.bytesExpected = bytes
        library.upsert(record)

        Task {
            let thumbnail = await ThumbnailService.makeThumbnail(for: destination, recordID: record.id)
            let duration = await ThumbnailService.duration(of: destination)
            library.update(record.id) { item in
                if let thumbnail { item.thumbnailName = thumbnail }
                if let duration { item.duration = duration }
            }
        }
        return record
    }
}
