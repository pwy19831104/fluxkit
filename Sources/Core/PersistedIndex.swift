import Foundation

/// Versioned, corruption-resistant JSON on disk.
///
/// Both the library index and the podcast subscriptions are a single JSON file. A decode failure
/// used to be indistinguishable from "nothing saved yet", and the next save then wrote an empty
/// array over the user's data — one bad byte or one added non-optional field meant a silently
/// wiped library.
///
/// What this does instead:
/// - the file is wrapped in an envelope carrying `schemaVersion`, so a future field change can
///   migrate rather than fail;
/// - a file that cannot be decoded is **moved aside** (`….corrupt-<timestamp>.json`) and never
///   overwritten, and the caller is told what happened;
/// - a file written by a *newer* build is left alone and saving is disabled, so downgrading the
///   app cannot destroy data either.
enum PersistedIndex {

    /// Bump when the on-disk shape changes. Readers accept everything up to this version.
    static let currentVersion = 1

    struct Envelope<Item: Codable>: Codable {
        var schemaVersion: Int
        var records: [Item]
    }

    struct LoadResult<Item> {
        var items: [Item] = []
        /// Localized, user-facing note when something had to be recovered or refused.
        var warning: String?
        /// `false` means the file on disk must not be replaced (newer schema, unreadable but
        /// preserved). Callers must honour this before saving.
        var canSave = true
        /// Where an unreadable file was moved, when that happened.
        var quarantinedURL: URL?
    }

    // MARK: - Load

    static func load<Item: Codable>(_ type: Item.Type, from url: URL, label: String) -> LoadResult<Item> {
        var result = LoadResult<Item>()
        guard FileManager.default.fileExists(atPath: url.path) else { return result }
        guard let data = try? Data(contentsOf: url) else {
            result.canSave = false
            result.warning = L("Couldn't read the \(label) file. Nothing was deleted.",
                               "无法读取\(label)文件，没有删除任何内容。")
            return result
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Current shape.
        if let envelope = try? decoder.decode(Envelope<Item>.self, from: data) {
            if envelope.schemaVersion > currentVersion {
                result.canSave = false
                result.warning = L("This \(label) file was written by a newer version of FluxKit. Update the app to open it.",
                                   "这个\(label)文件来自更新版本的 FluxKit，请更新 App 后再打开。")
                return result
            }
            result.items = envelope.records
            return result
        }

        // Legacy shape: a bare array (what every build before the envelope wrote).
        if let legacy = try? decoder.decode([Item].self, from: data) {
            result.items = legacy
            return result
        }

        // Unreadable: keep it, start empty, and say so.
        let backup = quarantine(url)
        result.quarantinedURL = backup
        result.warning = backup.map {
            L("The \(label) file was damaged, so it was backed up as “\($0.lastPathComponent)” and started fresh. Downloads on disk are untouched.",
              "\(label)文件已损坏，已备份为「\($0.lastPathComponent)」后重新开始。磁盘上的下载文件没有受到影响。")
        } ?? L("The \(label) file was damaged and started fresh.",
               "\(label)文件已损坏，已重新开始。")
        return result
    }

    private static func quarantine(_ url: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let candidate = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).\(ext)")
        do {
            try FileManager.default.moveItem(at: url, to: candidate)
            NSLog("PersistedIndex: quarantined \(url.lastPathComponent) -> \(candidate.lastPathComponent)")
            return candidate
        } catch {
            NSLog("PersistedIndex: could not quarantine \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Save

    @discardableResult
    static func save<Item: Codable>(_ items: [Item], to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(Envelope(schemaVersion: currentVersion, records: items)) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("PersistedIndex: save failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
}
