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


    /// `product.purchase()` can wait on the StoreKit daemon forever when the environment has no
    /// working StoreKit test service (observed on GitHub's macOS runners). `withThrowingTaskGroup`
    /// does **not** help: leaving the group waits for the uncancellable purchase task anyway, which
    /// turned a 30s deadline into a 105s stall. So the purchase runs in a detached task and the test
    /// polls a lock-protected box, returning as soon as the deadline passes.
    private func purchase(
        _ product: Product, seconds: UInt64 = 15
    ) async throws -> Product.PurchaseResult {
        let box = PurchaseBox()
        let task = Task.detached(priority: .userInitiated) {
            do { box.store(try await product.purchase()) } catch { box.fail(error) }
        }
        defer { task.cancel() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(Int64(seconds)))
        while clock.now < deadline {
            if let result = box.result() { return result }
            if let error = box.error() { throw error }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw StoreKitTestError.purchaseTimedOut(seconds)
    }

    private enum StoreKitTestError: Error, CustomStringConvertible {
        case purchaseTimedOut(UInt64)
        var description: String {
            switch self {
            case .purchaseTimedOut(let seconds):
                return "product.purchase() did not return within \(seconds)s — StoreKit test service unavailable"
            }
        }
    }

    private final class PurchaseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Product.PurchaseResult?
        private var failure: Error?

        func store(_ result: Product.PurchaseResult) {
            lock.lock(); defer { lock.unlock() }
            stored = result
        }

        func fail(_ error: Error) {
            lock.lock(); defer { lock.unlock() }
            failure = error
        }

        func result() -> Product.PurchaseResult? {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        func error() -> Error? {
            lock.lock(); defer { lock.unlock() }
            return failure
        }
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
    ///
    /// Skipped on CI: GitHub's macOS runners have no working StoreKit test daemon, so
    /// `product.purchase()` never returns there (verified in run 42120249948). The deterministic
    /// contract tests above still run everywhere; the interactive purchase is covered locally and
    /// by the sandbox cases in `docs/TEST_PLAN.md`.
    func testPurchaseBecomesCurrentEntitlement() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: [Expected.monthly])
        let product = try XCTUnwrap(products.first)

        let purchaseResult: Product.PurchaseResult
        do {
            purchaseResult = try await purchase(product)
        } catch StoreKitTestError.purchaseTimedOut {
            throw XCTSkip(
                "StoreKit test service unavailable here (no daemon response); covered by the sandbox cases in docs/TEST_PLAN.md"
            )
        }

        switch purchaseResult {
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
    /// Two flows are deliberately *not* asserted here, because the test session behaves unlike a
    /// real device: `expireSubscription` kept the status snapshot at `.subscribed`, and purchasing a
    /// second plan while one is active returned the already-purchased transaction instead of an
    /// upgrade transaction. Both are covered by the manual sandbox cases PRO-05..PRO-08 in
    /// `docs/TEST_PLAN.md` and by RevenueCat's server-side entitlement, which is what actually gates
    /// the app.
    func testUnknownProductIDIsNotResolved() async throws {
        _ = try makeSession()

        let products = try await Product.products(for: ["cloud.fluxkit.pro.does-not-exist"])
        XCTAssertTrue(products.isEmpty, "An unknown product ID should resolve to nothing")
    }
}
