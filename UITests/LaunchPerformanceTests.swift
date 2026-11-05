import XCTest

/// PERF-01: cold launch budget (test plan target: ≤1.5s on iPhone 12 and newer).
///
/// Runs in the UI test target because `XCTApplicationLaunchMetric` needs a real app launch.
final class LaunchPerformanceTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testColdLaunchPerformance() {
        let app = XCUIApplication()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
            app.terminate()
        }
    }
}
