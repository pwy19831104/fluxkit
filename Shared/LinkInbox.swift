import Foundation

/// Hand-off queue between the share extension and the app.
///
/// The previous implementation kept a `[String]` in `UserDefaults` and did
/// `read array → append → write array`, which is a read-modify-write race: a link pushed by the
/// extension could be dropped by a `popNewest()` running in the app at the same moment (and vice
/// versa). TWO processes sharing one small container make that window easy to hit — sharing five
/// links quickly while the app is launching is enough.
///
/// This version stores **one file per link**. Creating a distinct file needs no lock and cannot
/// lose an update; popping deletes the newest file and treats "already deleted" as a retry.
///
/// Ordering comes from the file name (`<seconds since epoch>` with millisecond precision + a random
/// suffix), so a lexicographic sort is chronological, even across processes whose clocks agree.
struct LinkInbox {

    /// Older links are dropped so a stuck consumer cannot grow the container forever.
    static let limit = 20

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Writing

    /// Adds a link. Consecutive duplicates are ignored, matching the old behaviour.
    @discardableResult
    func push(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let newest = newestName(), let current = read(newest), current == trimmed { return false }

        let name = Self.makeName()
        do {
            try Data(trimmed.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        trimToLimit()
        return true
    }

    /// Removes and returns the newest link, or `nil` when the inbox is empty.
    func popNewest() -> String? {
        for name in names().reversed() {
            let url = directory.appendingPathComponent(name)
            // Another process may have taken it between listing and deleting: skip and try the
            // next one instead of reporting a failure.
            if let link = read(name) {
                try? fileManager.removeItem(at: url)
                return link
            }
            try? fileManager.removeItem(at: url)
        }
        return nil
    }

    var count: Int { names().count }

    /// All pending links, oldest first. Used by tests and by the debug harness.
    func pendingLinks() -> [String] {
        names().compactMap { read($0) }
    }

    // MARK: - Migration

    /// Moves links left behind by the `UserDefaults`-based inbox into files, then removes the key.
    /// Safe to call repeatedly: it only acts when the legacy array exists.
    func migrate(legacyLinks: [String]?) {
        guard let legacyLinks, !legacyLinks.isEmpty else { return }
        for link in legacyLinks where !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            push(link)
        }
    }

    // MARK: - Files

    private func names() -> [String] {
        let all = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return all.filter { $0.hasSuffix(Self.suffix) }.sorted()
    }

    private func newestName() -> String? { names().last }

    private func read(_ name: String) -> String? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func trimToLimit() {
        let names = names()
        guard names.count > Self.limit else { return }
        for name in names.prefix(names.count - Self.limit) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static let suffix = ".link"

    /// Nanosecond resolution, zero padded so a lexicographic sort is chronological. Millisecond
    /// timestamps were not enough: a burst of pushes landed in the same millisecond and the random
    /// suffix then decided the order, so `popNewest()` could hand back an older link first.
    private static func makeName() -> String {
        let nanos = clock_gettime_nsec_np(CLOCK_REALTIME)
        return String(format: "%020llu-%@%@", nanos, UUID().uuidString, suffix)
    }
}
