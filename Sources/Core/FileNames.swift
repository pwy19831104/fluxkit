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
        if cleaned.count > 70 {
            cleaned = String(cleaned.prefix(70)).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? "Video" : cleaned
    }

    /// A unique name inside `directory`, keeping the given extension.
    static func uniqueName(title: String, extension ext: String, in directory: URL, recordID: UUID) -> String {
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
    static func adopt(fileName: String, title: String, recordID: UUID) -> String {
        let directory = AppPaths.downloads
        let source = directory.appendingPathComponent(fileName)
        let ext = source.pathExtension
        let target = uniqueName(title: title, extension: ext, in: directory, recordID: recordID)
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
