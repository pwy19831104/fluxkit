import Foundation

/// Hand-off area between the share extension and the app, backed by an App Group.
enum SharedInbox {
    static let appGroupIdentifier = "group.com.downloadkit.app"

    private static let key = "pendingLinks"
    private static let limit = 20

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
    }

    /// Called by the share extension.
    static func push(_ link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let defaults else { return }
        var links = defaults.stringArray(forKey: key) ?? []
        if links.last == trimmed { return }
        links.append(trimmed)
        if links.count > limit { links = Array(links.suffix(limit)) }
        defaults.set(links, forKey: key)
    }

    /// Called by the app when it becomes active.
    static func popNewest() -> String? {
        guard let defaults else { return nil }
        var links = defaults.stringArray(forKey: key) ?? []
        guard let newest = links.popLast() else { return nil }
        defaults.set(links, forKey: key)
        return newest
    }

    static var pendingCount: Int {
        defaults?.stringArray(forKey: key)?.count ?? 0
    }
}
