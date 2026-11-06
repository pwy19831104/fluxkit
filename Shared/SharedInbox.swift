import Foundation

/// Hand-off area between the share extension and the app, backed by an App Group.
///
/// The storage itself lives in `LinkInbox` (file per link) so that concurrent pushes and pops from
/// two processes cannot lose an entry; this type only resolves the shared directory and keeps the
/// `UserDefaults`-based migration for installs that still have pending links from older builds.
enum SharedInbox {
    static let appGroupIdentifier = "group.cloud.fluxkit.app"

    /// Legacy key used by the `UserDefaults` inbox (pre-1.0 file inbox).
    static let legacyKey = "pendingLinks"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    private static var inbox: LinkInbox? {
        guard let base = containerURL else { return nil }
        return LinkInbox(directory: base.appendingPathComponent("Links", isDirectory: true))
    }

    private static let migrateOnce: Void = {
        guard let inbox, let defaults else { return }
        let legacy = defaults.stringArray(forKey: legacyKey)
        if let legacy, !legacy.isEmpty {
            inbox.migrate(legacyLinks: legacy)
        }
        defaults.removeObject(forKey: legacyKey)
    }()

    /// Called by the share extension.
    @discardableResult
    static func push(_ link: String) -> Bool {
        _ = migrateOnce
        return inbox?.push(link) ?? false
    }

    /// Called by the app when it becomes active.
    static func popNewest() -> String? {
        _ = migrateOnce
        return inbox?.popNewest()
    }

    static var pendingCount: Int {
        _ = migrateOnce
        return inbox?.count ?? 0
    }
}
