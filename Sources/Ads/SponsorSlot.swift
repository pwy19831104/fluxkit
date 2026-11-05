import SwiftUI

/// The single ad surface used across the app.
///
/// Nothing here talks to an ad network yet. To go live:
/// 1. Add the provider SDK (e.g. Google Mobile Ads via SPM).
/// 2. Replace `placeholder` below with the SDK's banner/native view, using the
///    unit IDs from `AdsConfig`.
/// 3. Flip `AdsConfig.isEnabled` and follow the checklist in `docs/ADS.md`.
struct SponsorSlot: View {
    enum Style { case banner, native }

    var style: Style = .banner

    var body: some View {
        if AdsConfig.isEnabled || AdsConfig.showsPlaceholder {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Text(L("SPONSORED", "广告"))
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
            Text(L("Ad space", "广告位"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: style == .banner ? 64 : 96)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Theme.stroke,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Advertisement", "广告"))
    }
}
