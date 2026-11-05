import XCTest
import StoreKit
import StoreKitTest

/// Guards the product setup: the IDs in `Configuration.storekit` must match what App Store Connect
/// and RevenueCat are configured with, must be auto-renewable, and must live in one subscription
/// group (so a user can switch monthly ↔ yearly without a second subscription).
///
/// The app itself does not hard-code product IDs any more — RevenueCat's offering supplies the
/// packages — so this file is where the naming contract is written down. If you rename a product
/// in App Store Connect, update it here, in `Configuration.storekit`, and in RevenueCat together.
///
/// Note: production purchases go through RevenueCat; this configuration only makes StoreKit answer
/// locally (simulator, no network, no charges).
final class StoreKitConfigurationTests: XCTestCase {

    private enum Expected {
        static let monthly = "cloud.fluxkit.pro.monthly"
        static let yearly = "cloud.fluxkit.pro.yearly"
        static var all: [String] { [monthly, yearly] }
    }

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Configuration")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// The configured products must be exactly the two IDs App Store Connect declares.
    func testConfiguredProductsMatchTheDeclaredIDs() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: Expected.all)
        XCTAssertEqual(
            Set(products.map { $0.id }),
            Set(Expected.all),
            "Configuration.storekit must declare exactly the expected product IDs"
        )
    }

    func testSubscriptionsHavePricePeriodAndSharedGroup() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: Expected.all)
        XCTAssertEqual(products.count, 2)

        var groupIDs: Set<String> = []

        for product in products {
            XCTAssertGreaterThan(product.price, 0, "\(product.id) has no price")

            guard let subscription = product.subscription else {
                return XCTFail("\(product.id) is not an auto-renewable subscription")
            }

            let unit = subscription.subscriptionPeriod.unit
            let expectedUnit: Product.SubscriptionPeriod.Unit =
                product.id == Expected.monthly ? .month : .year
            XCTAssertEqual(unit, expectedUnit, "\(product.id) has the wrong period")

            groupIDs.insert(subscription.subscriptionGroupID)
        }

        XCTAssertEqual(
            groupIDs.count, 1,
            "Both products must sit in one subscription group so upgrades work"
        )
    }

    /// A purchase in the test session must produce a verified transaction that survives `finish()`
    /// and shows up as a current entitlement — the same check `ProStore` relies on.
    func testPurchaseBecomesCurrentEntitlement() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: [Expected.monthly])
        let product = try XCTUnwrap(products.first)

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return XCTFail("Transaction failed verification")
            }
            XCTAssertEqual(transaction.productID, Expected.monthly)
            await transaction.finish()

            var found = false
            for await entitlement in Transaction.currentEntitlements {
                if case .verified(let active) = entitlement, active.productID == Expected.monthly {
                    found = true
                }
            }
            XCTAssertTrue(found, "Purchased subscription should be a current entitlement")

        case .userCancelled:
            XCTFail("Test session cancelled the purchase unexpectedly")
        case .pending:
            XCTFail("Purchase stayed pending in the test session")
        @unknown default:
            XCTFail("Unexpected purchase result")
        }
    }

    /// Negative case: an ID that is not in the configuration must not resolve, so a typo in the
    /// paywall or in the RevenueCat offering fails loudly instead of silently showing a product.
    ///
    /// Expiry (`SKTestSession.expireSubscription`) is deliberately *not* asserted here: on this SDK
    /// the subscription status snapshot kept reporting `.subscribed` after the call, which makes the
    /// assertion flaky. Expiry/refund handling is covered by the manual cases PRO-06/PRO-07 in
    /// `docs/TEST_PLAN.md` plus RevenueCat's server notifications.
    func testUnknownProductIDIsNotResolved() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: ["cloud.fluxkit.pro.does-not-exist"])
        XCTAssertTrue(products.isEmpty, "An unknown product ID should resolve to nothing")
    }
}
