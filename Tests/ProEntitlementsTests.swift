import XCTest
@testable import FluxKit

final class ProEntitlementsTests: XCTestCase {

    func testFreePlanIsLimitedToOneDownload() {
        XCTAssertEqual(ProEntitlements.effectiveConcurrency(configured: 4, isPro: false), 1)
        XCTAssertEqual(ProEntitlements.effectiveConcurrency(configured: 2, isPro: false), 1)
    }

    func testProUsesConfiguredConcurrencyWithinBounds() {
        XCTAssertEqual(ProEntitlements.effectiveConcurrency(configured: 3, isPro: true), 3)
        XCTAssertEqual(ProEntitlements.effectiveConcurrency(configured: 0, isPro: true), 1)
        XCTAssertEqual(ProEntitlements.effectiveConcurrency(configured: 99, isPro: true), 4)
    }

    func testAutoDownloadRequiresPro() {
        XCTAssertEqual(ProEntitlements.effectiveAutoDownload(configured: 5, isPro: false), 0)
        XCTAssertEqual(ProEntitlements.effectiveAutoDownload(configured: 5, isPro: true), 5)
        XCTAssertFalse(ProEntitlements.allowsAutoDownload(isPro: false))
        XCTAssertTrue(ProEntitlements.allowsAutoDownload(isPro: true))
    }

    func testCatalogIDsAreStable() {
        XCTAssertEqual(ProCatalog.monthlyID, "cloud.streamkit.pro.monthly")
        XCTAssertEqual(ProCatalog.yearlyID, "cloud.streamkit.pro.yearly")
    }
}
