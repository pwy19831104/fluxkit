import Foundation

enum FileNames {
    /// Turns a title into a friendly, Finder/Files-safe file name.
    static func sanitize(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Limit by UTF-8 bytes, not characters: APFS caps a name at 255 bytes, and 70 emoji would
        // be 280 — the write would fail and the file would fall back to its UUID name.
        let byteLimit = 180
        if cleaned.utf8.count > byteLimit {
            while cleaned.utf8.count > byteLimit, !cleaned.isEmpty {
                cleaned.removeLast()
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        // A leading dot would make the file invisible in Files.app.
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? "Video" : cleaned
    }

    /// A unique name inside `directory`, keeping the given extension.
    static func uniqueName(title: String, extension ext: String, in directory: URL) -> String {
        let base = sanitize(title)
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = base + suffix
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(counter))\(suffix)"
            counter += 1
        }
        return candidate
    }

    /// Renames a freshly finished download to its title, falling back to the original
    /// name when the move fails. Returns the name to store on the record.
    ///
    /// - Parameter referenced: names other records already own. A file on disk that nobody
    ///   references is a leftover (see `MediaSweep`), so it is reclaimed instead of forcing the new
    ///   download to `Title (2).mp4`. Without this, every pause/resume cycle both duplicated the
    ///   media and left the previous copy orphaned.
    static func adopt(
        fileName: String,
        title: String,
        referenced: Set<String> = [],
        recordID: UUID
    ) -> String {
        let directory = AppPaths.downloads
        let source = directory.appendingPathComponent(fileName)
        let ext = source.pathExtension
        let base = sanitize(title)
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var target = base + suffix
        var counter = 2
        while true {
            let candidateURL = directory.appendingPathComponent(target)
            let isSource = target == fileName
            if isSource { break }
            if !FileManager.default.fileExists(atPath: candidateURL.path) { break }
            if !referenced.contains(target) {
                // Leftover from an earlier attempt: take the name back.
                try? FileManager.default.removeItem(at: candidateURL)
                break
            }
            target = "\(base) (\(counter))\(suffix)"
            counter += 1
        }

        guard target != fileName else { return fileName }
        let destination = directory.appendingPathComponent(target)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return target
        } catch {
            return fileName
        }
    }
}
