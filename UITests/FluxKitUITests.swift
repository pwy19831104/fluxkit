import XCTest
import UIKit

final class FluxKitUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = [], pasteSeed: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        var environment = ["APP_LANGUAGE": "en"]
        // The app seeds its own pasteboard from this: a test runner's `UIPasteboard.general`
        // write is a cross-process write, and iOS refuses the app's read of it.
        if let pasteSeed { environment["PASTE_SEED"] = pasteSeed }
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    func testHomeShowsCoreActions() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["home-link-field"].exists)
        XCTAssertTrue(app.buttons["home-paste"].exists)
        XCTAssertTrue(app.buttons["home-download"].exists)
        XCTAssertTrue(app.tabBars.buttons["Podcasts"].exists)
    }

    /// The add-podcast sheet offers Paste next to Add, and pasting fills the field (it does not
    /// submit), so a feed URL from the clipboard can be reviewed before it is added.
    func testAddPodcastSheetCanPasteFromClipboard() throws {
        let link = "https://feeds.npr.org/510289/podcast.xml"
        let app = launch(pasteSeed: link)
        app.tabBars.buttons["Podcasts"].tap()

        let add = app.buttons["Add podcast"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        XCTAssertTrue(app.buttons["podcast-add"].waitForExistence(timeout: 5))
        let paste = app.buttons["podcast-paste"]
        XCTAssertTrue(paste.exists)
        paste.tap()

        let field = app.textFields["podcast-feed-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, link)
    }

    /// The Download tab's Paste button is a `PasteButton`: tapping it fills the field with the
    /// link from the clipboard (and, unlike a programmatic read, needs no permission prompt).
    func testHomePasteFillsTheLinkField() throws {
        let link = "https://tv.sohu.com/v/MjAyNjExMDQvbjYyMDI2OTUxNi5zaHRtbA==.html"
        let app = launch(pasteSeed: link)

        let paste = app.buttons["home-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()

        let field = app.textFields["home-link-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, link)
    }

    func testSettingsShowsQueuePodcastAndNotificationOptions() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.switches["settings-wifi-only"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["At the same time"].exists)
        XCTAssertTrue(app.buttons["settings-export-opml"].exists)
        XCTAssertTrue(app.buttons["settings-import-opml"].exists)
        XCTAssertTrue(app.switches["settings-notify"].exists)
    }

    func testPaywallOpensFromSettings() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()

        let upgrade = app.buttons["settings-pro-upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        upgrade.tap()

        XCTAssertTrue(app.navigationBars["FluxKit Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
    }

    func testProUnlockHidesUpgradeButton() {
        let app = launch(["-proUnlocked"])
        app.tabBars.buttons["Settings"].tap()

        let status = app.staticTexts["settings-pro-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Pro is active")
        XCTAssertFalse(app.buttons["settings-pro-upgrade"].exists)
    }

    func testLibrarySearchFiltersSeededItems() {
        let app = launch(["-seedLibrary"])
        app.tabBars.buttons["Library"].tap()

        XCTAssertTrue(app.staticTexts["Alpha Clip"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bravo Clip"].exists)
        XCTAssertTrue(app.staticTexts["Charlie Clip"].exists)

        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Bravo")

        XCTAssertTrue(app.staticTexts["Bravo Clip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alpha Clip"].exists)
        XCTAssertFalse(app.staticTexts["Charlie Clip"].exists)
    }

    func testLibrarySelectionModeIsAvailable() {
        let app = launch(["-seedLibrary"])
        app.tabBars.buttons["Library"].tap()

        let select = app.buttons["library-select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["library-sort"].exists)
    }
}
