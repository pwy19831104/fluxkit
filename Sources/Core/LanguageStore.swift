import Foundation
import Observation

/// Observable wrapper around the language choice so the whole UI can re-render when the user
/// switches language. Defaults to the device region; a manual pick is persisted.
@MainActor
@Observable
final class LanguageStore {

    static let shared = LanguageStore()

    /// The language the UI should render right now.
    private(set) var language: AppLanguage

    /// `nil` means "follow the device region".
    private(set) var override: AppLanguage?

    private init() {
        let stored = LanguagePreferences.override
        override = stored
        language = AppLanguage.effective(regionIdentifier: Locale.current.region?.identifier,
                                         override: stored)
    }

    func set(_ language: AppLanguage) {
        guard language != self.language else { return }
        override = language
        LanguagePreferences.override = language
        self.language = language
    }

    /// True while no manual choice has been made (the region decides).
    var isFollowingRegion: Bool { override == nil }
}
