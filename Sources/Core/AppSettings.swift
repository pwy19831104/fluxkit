import Foundation
import Observation

/// User preferences that affect downloads, podcasts and playback.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let wifiOnly = "fluxkit.wifiOnly"
        static let maxConcurrent = "fluxkit.maxConcurrent"
        static let notifyOnFinish = "fluxkit.notifyOnFinish"
        static let podcastAutoDownload = "fluxkit.podcastAutoDownload"
        static let playbackSpeed = "fluxkit.playbackSpeed"
    }

    /// Queue and only download over Wi-Fi.
    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Key.wifiOnly) }
    }

    /// How many downloads run at the same time (clamped to 1…4 on read).
    ///
    /// The clamp used to live in `didSet`, which re-entered the setter; a computed property over
    /// the stored value is both simpler and still observable.
    var maxConcurrentDownloads: Int {
        get { min(max(storedMaxConcurrentDownloads, 1), ProEntitlements.maxProConcurrency) }
        set {
            storedMaxConcurrentDownloads = newValue
            defaults.set(newValue, forKey: Key.maxConcurrent)
        }
    }
    private var storedMaxConcurrentDownloads: Int

    /// Local notification when a background download finishes or fails.
    var notifyOnFinish: Bool {
        didSet {
            defaults.set(notifyOnFinish, forKey: Key.notifyOnFinish)
            if notifyOnFinish {
                Task { await DownloadNotifications.requestAuthorization() }
            }
        }
    }

    /// Automatically download the newest N episodes when a subscribed feed refreshes.
    var podcastAutoDownload: Int {
        didSet { defaults.set(podcastAutoDownload, forKey: Key.podcastAutoDownload) }
    }

    /// Last playback speed chosen in the player.
    var playbackSpeed: Double {
        didSet { defaults.set(playbackSpeed, forKey: Key.playbackSpeed) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wifiOnly = defaults.bool(forKey: Key.wifiOnly)
        let concurrency = defaults.integer(forKey: Key.maxConcurrent)
        storedMaxConcurrentDownloads = concurrency == 0 ? 2 : concurrency
        notifyOnFinish = defaults.bool(forKey: Key.notifyOnFinish)
        podcastAutoDownload = defaults.integer(forKey: Key.podcastAutoDownload)
        let speed = defaults.double(forKey: Key.playbackSpeed)
        playbackSpeed = speed == 0 ? 1 : speed
    }
}
