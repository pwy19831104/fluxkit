import Foundation
import Observation
import RevenueCat

enum ProConfig {
    /// Public RevenueCat SDK key (`appl_…`). Stored in Info.plist so it can differ per build.
    static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Entitlement identifier configured in the RevenueCat dashboard.
    static let entitlementID = "pro"

    static var isTestStoreKey: Bool {
        apiKey.hasPrefix("test_")
    }

    static var isConfigured: Bool {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("REPLACE"), !apiKey.hasPrefix("YOUR_") else {
            return false
        }
        #if DEBUG
        return true
        #else
        // A RevenueCat Test Store key must never ship: purchases would be simulated.
        return !isTestStoreKey
        #endif
    }
}

/// RevenueCat-backed entitlement + offerings. RevenueCat wraps StoreKit 2 internally,
/// so purchases still go through Apple and receipts are validated by RevenueCat.
@MainActor
@Observable
final class ProStore {

    static let shared = ProStore()

    private(set) var isPro = false
    private(set) var packages: [Package] = []
    private(set) var offering: Offering?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let isConfigured: Bool
    private let forcedPro: Bool

    private var streamTask: Task<Void, Never>?

    private init() {
        #if DEBUG
        forcedPro = ProcessInfo.processInfo.arguments.contains("-proUnlocked")
        #else
        forcedPro = false
        #endif
        isConfigured = ProConfig.isConfigured
        isPro = forcedPro

        guard isConfigured else { return }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: ProConfig.apiKey)

        Task { [weak self] in
            await self?.refreshOfferings()
            await self?.refreshEntitlements()
        }
        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                self.apply(info)
            }
        }
    }

    // MARK: - Offerings

    func refreshOfferings() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            packages = offerings.current?.availablePackages ?? []
            if packages.isEmpty {
                errorMessage = L("No subscription packages are configured in RevenueCat.",
                                 "RevenueCat 中还没有配置订阅包。")
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        guard isConfigured else {
            errorMessage = L("RevenueCat isn't configured in this build.",
                             "此构建尚未配置 RevenueCat。")
            return false
        }
        errorMessage = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            apply(result.customerInfo)
            return isPro
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        if forcedPro {
            isPro = true
            return
        }
        guard isConfigured else {
            isPro = false
            return
        }
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ info: CustomerInfo) {
        if forcedPro {
            isPro = true
            return
        }
        isPro = info.entitlements.active[ProConfig.entitlementID]?.isActive == true
    }

    #if DEBUG
    var debugForcedPro: Bool { forcedPro }
    #endif
}
