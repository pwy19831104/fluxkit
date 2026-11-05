import RevenueCat
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var purchasingID: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    features
                    plans
                    restore
                    disclaimer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("FluxKit Pro", "FluxKit Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close", "关闭")) { dismiss() }
                }
            }
            .task {
                if pro.packages.isEmpty { await pro.refreshOfferings() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ProConfig.isTestStoreKey {
                Text(L("RevenueCat Test Store — purchases are simulated.",
                       "RevenueCat 测试商店 —— 购买为模拟行为。"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.surfaceRaised))
            }
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Do more with FluxKit", "用 FluxKit 做更多"))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("One subscription. No ads. Ever.", "一次订阅，永久无广告。"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if pro.isPro {
                Label(L("Pro is active on this Apple ID.", "此 Apple ID 已解锁 Pro。"),
                      systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.success)
            }
        }
        .paywallCard()
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("square.stack.3d.down.right.fill",
                    L("Up to 4 downloads at once", "最多 4 个任务同时下载"),
                    L("Queue the rest and let them start automatically.", "其余任务自动排队开始。"))
            feature("arrow.down.circle.fill",
                    L("Podcast auto-download", "播客自动下载"),
                    L("Keep the newest 1/3/5 episodes ready for offline listening.", "自动保留最新 1/3/5 期节目。"))
            feature("bolt.heart.fill",
                    L("Support development", "支持持续开发"),
                    L("No ads, no tracking — your subscription keeps it that way.", "没有广告、没有追踪。"))
        }
        .paywallCard()
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(pro.packages, id: \.identifier) { package in
                planButton(package)
            }
            if pro.packages.isEmpty {
                Text(pro.isConfigured
                     ? L("No offerings are available right now. Create an offering in RevenueCat and try again.",
                         "当前没有可用的订阅方案。请在 RevenueCat 中创建 Offering 后重试。")
                     : L("RevenueCat isn't configured in this build. Add your public SDK key to REVENUECAT_API_KEY.",
                         "此构建尚未配置 RevenueCat。请在 REVENUECAT_API_KEY 中填入公开 SDK Key。"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = pro.errorMessage {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planButton(_ package: Package) -> some View {
        let product = package.storeProduct
        return Button {
            guard purchasingID == nil else { return }
            purchasingID = package.identifier
            Task {
                let success = await pro.purchase(package)
                purchasingID = nil
                if success { dismiss() }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: package))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Auto-renewing subscription", "自动续期订阅"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                if purchasingID == package.identifier {
                    ProgressView()
                } else {
                    Text(product.localizedPriceString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasingID != nil)
    }

    private func title(for package: Package) -> String {
        switch package.packageType {
        case .monthly: return L("Monthly", "按月")
        case .annual: return L("Yearly", "按年")
        case .lifetime: return L("Lifetime", "永久")
        default: return package.storeProduct.localizedTitle
        }
    }

    private var restore: some View {
        Button {
            Task { await pro.restore() }
        } label: {
            Text(L("Restore purchases", "恢复购买"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
        }
        .disabled(pro.isLoading)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Payment is charged to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the period ends. Manage it in Settings → Apple ID → Subscriptions.",
                   "费用由 Apple ID 扣款；订阅会自动续期，可在「设置 → Apple ID → 订阅」中管理或取消。"))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                if let terms = LegalLinks.terms {
                    Link(L("Terms of Use", "使用条款"), destination: terms)
                }
                if let privacy = LegalLinks.privacyPolicy {
                    Link(L("Privacy Policy", "隐私政策"), destination: privacy)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .tint(Theme.accent)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PaywallCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func paywallCard() -> some View { modifier(PaywallCard()) }
}
