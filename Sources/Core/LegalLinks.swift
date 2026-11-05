import Foundation

/// Legal URLs injected through Info.plist so the app never ships dead links.
/// Fill `SKPrivacyPolicyURL` and `SKTermsURL` in `project.yml` before submitting.
enum LegalLinks {
    static var privacyPolicy: URL? { url(forInfoKey: "SKPrivacyPolicyURL") }
    static var terms: URL? { url(forInfoKey: "SKTermsURL") }

    private static func url(forInfoKey key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }
}
