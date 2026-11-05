import Foundation

/// Ad configuration.
///
/// Ads ship **off**. Wire up a provider (see `docs/ADS.md`), paste your unit IDs
/// below, then flip `isEnabled`. `SponsorSlot` is the only place that renders an
/// ad, so swapping in a real SDK view is a one-file change.
enum AdsConfig {

    /// Master switch. Keep `false` until the provider SDK is linked and consent
    /// handling (ATT / UMP) is in place.
    static let isEnabled = false

    /// Test unit IDs from the provider console. Replace with production IDs.
    static let homeBannerUnitID = "ca-app-pub-0000000000000000/0000000000"
    static let downloadsBannerUnitID = "ca-app-pub-0000000000000000/0000000000"
    static let libraryNativeUnitID = "ca-app-pub-0000000000000000/0000000000"

    /// Renders the dashed placeholder so the layout can be reviewed before an
    /// SDK is added. Works in Debug builds only.
    static var showsPlaceholder: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SHOW_AD_SLOT"] == "1"
        #else
        false
        #endif
    }
}
