import Foundation

/// Pure gating rules so they can be unit-tested without StoreKit.
enum ProEntitlements {
    static let maxFreeConcurrency = 1
    static let maxProConcurrency = 4

    static func effectiveConcurrency(configured: Int, isPro: Bool) -> Int {
        let clamped = min(max(configured, 1), maxProConcurrency)
        return isPro ? clamped : maxFreeConcurrency
    }

    static func allowsAutoDownload(isPro: Bool) -> Bool { isPro }

    static func effectiveAutoDownload(configured: Int, isPro: Bool) -> Int {
        isPro ? max(configured, 0) : 0
    }
}
