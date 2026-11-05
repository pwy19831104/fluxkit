import XCTest
@testable import FluxKit

@MainActor
final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "fluxkit.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.wifiOnly)
        XCTAssertEqual(settings.maxConcurrentDownloads, 2)
        XCTAssertFalse(settings.notifyOnFinish)
        XCTAssertEqual(settings.podcastAutoDownload, 0)
        XCTAssertEqual(settings.playbackSpeed, 1, accuracy: 0.001)
    }

    func testConcurrencyIsClamped() {
        let settings = AppSettings(defaults: defaults)
        settings.maxConcurrentDownloads = 9
        XCTAssertEqual(settings.maxConcurrentDownloads, 4)
        settings.maxConcurrentDownloads = 0
        XCTAssertEqual(settings.maxConcurrentDownloads, 1)
    }

    func testPreferencesPersist() {
        let first = AppSettings(defaults: defaults)
        first.wifiOnly = true
        first.maxConcurrentDownloads = 3
        first.podcastAutoDownload = 5
        first.playbackSpeed = 1.5

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.wifiOnly)
        XCTAssertEqual(second.maxConcurrentDownloads, 3)
        XCTAssertEqual(second.podcastAutoDownload, 5)
        XCTAssertEqual(second.playbackSpeed, 1.5, accuracy: 0.001)
    }
}
