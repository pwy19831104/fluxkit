import Foundation

/// The two shipped languages.
///
/// Default comes from the **region** (mainland China → Simplified Chinese, everywhere else →
/// English), but the user can override it from the globe menu on the home screen. The override is
/// persisted in the shared App Group defaults, so the share extension follows the same choice.
enum AppLanguage: String, CaseIterable, Hashable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    // MARK: - Resolution

    /// Pure, so it can be unit-tested for every region.
    static func resolve(regionIdentifier: String?) -> AppLanguage {
        regionIdentifier?.uppercased() == "CN" ? .chinese : .english
    }

    /// A manual choice always wins over the region.
    static func effective(regionIdentifier: String?, override: AppLanguage?) -> AppLanguage {
        override ?? resolve(regionIdentifier: regionIdentifier)
    }

    /// The language the device region asks for.
    static var region: AppLanguage {
        resolve(regionIdentifier: Locale.current.region?.identifier)
    }

    /// What the UI should render right now.
    static var current: AppLanguage {
        #if DEBUG
        // Screenshot / UI-test hook: `SIMCTL_CHILD_APP_LANGUAGE=zh`.
        switch ProcessInfo.processInfo.environment["APP_LANGUAGE"]?.lowercased() {
        case "zh", "zh-hans", "cn": return .chinese
        case "en": return .english
        default: break
        }
        #endif
        return effective(regionIdentifier: Locale.current.region?.identifier,
                         override: LanguagePreferences.override)
    }

    /// Used for `RelativeDateTimeFormatter`, …
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .chinese: return Locale(identifier: "zh_Hans_CN")
        }
    }

    /// Always written in the language itself, so both options are readable in the switcher.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

// MARK: - Persistence

/// Stores the user's manual language choice. Uses the App Group defaults so the share extension
/// renders in the same language as the app.
enum LanguagePreferences {
    static let defaultsKey = "fluxkit.language.override"

    static var defaults: UserDefaults {
        SharedInbox.defaults ?? .standard
    }

    static var override: AppLanguage? {
        get { override(in: defaults) }
        set { setOverride(newValue, in: defaults) }
    }

    static func override(in defaults: UserDefaults) -> AppLanguage? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        return AppLanguage(rawValue: raw)
    }

    static func setOverride(_ language: AppLanguage?, in defaults: UserDefaults) {
        guard let language else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(language.rawValue, forKey: defaultsKey)
    }
}

/// Two-string lookup: `L("English copy", "中文文案")`.
///
/// No `.strings` files on purpose — the language follows the region plus an explicit user
/// override, so a plain lookup keeps the behaviour obvious and testable.
func L(_ english: String, _ chinese: String, language: AppLanguage = .current) -> String {
    language == .chinese ? chinese : english
}
