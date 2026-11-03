import Foundation

/// Bridges the background-session completion handler delivered to the app delegate
/// over to the `URLSession` delegate, which is the only place iOS allows it to be called.
enum BackgroundSessionBridge {
    static let identifier = "com.downloadkit.app.background"

    private static let lock = NSLock()
    private static var storedHandler: (() -> Void)?

    static func store(_ handler: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        storedHandler = handler
    }

    static func consume() -> (() -> Void)? {
        lock.lock(); defer { lock.unlock() }
        let handler = storedHandler
        storedHandler = nil
        return handler
    }
}
