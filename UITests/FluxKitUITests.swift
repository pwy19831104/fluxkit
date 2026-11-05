import XCTest

final class FluxKitUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment = ["APP_LANGUAGE": "en"]
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
