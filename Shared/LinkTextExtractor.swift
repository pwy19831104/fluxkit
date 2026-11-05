import Foundation

/// Finds the first web address inside arbitrary text.
///
/// Share sheets (especially Chinese apps) copy a whole blurb, not a clean URL:
///
///     5.33 复制打开抖音，看看【水泥美的作品】…# ai # ai工具
///     https://v.douyin.com/AfPLqZg3RJo/ w@S.LJ :6pm icN:/ 09/29
///
/// Both the paste box and the share extension run this first, so the user never has to
/// hand-clean the text. Lives in `Shared/` because the extension needs it too.
enum LinkTextExtractor {

    /// Characters that can follow a URL in prose but never belong to it.
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?、，。；：！？)]}>\"'”’》」』】）")

    /// Anything that separates a URL from the surrounding text: whitespace, quotes, full-width
    /// punctuation, and CJK characters (Chinese prose puts no space before a link).
    private static let separators = "\\s<>\"'`，。；：！？、（）【】《》「」『』　\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}"

    private static let schemePrefix = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9+.\\-]*:")

    static func firstLink(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // The whole string is already a link (possibly without a scheme, e.g. "v.douyin.com/x").
        let hasScheme = schemePrefix.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)) != nil
        if !hasScheme,
           trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           let url = LinkURL.normalized(from: trimmed) {
            return url.absoluteString
        }

        for candidate in candidates(in: trimmed) {
            if let url = LinkURL.normalized(from: candidate) {
                return url.absoluteString
            }
        }
        return nil
    }

    // MARK: - Candidate scanning

    /// Explicit `http(s)` links win, then bare domains, and Foundation's detector is the safety
    /// net for wrappers like `<https://…>`.
    private static func candidates(in text: String) -> [String] {
        var results: [String] = []

        results += matches(pattern: "https?://[^\(separators)]+", in: text)

        // Bare domains: v.douyin.com/AfPLqZg3RJo, example.com/clip.mp4, …
        // The look-behind keeps us from matching inside e-mail addresses, schemes or words.
        results += matches(
            pattern: "(?<![\\w@/.\\-:])(?:[a-zA-Z0-9](?:[a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)+(?:[a-zA-Z]{2,24})(?::\\d{2,5})?(?:/[^\(separators)]*)?",
            in: text
        )

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            results += detector.matches(in: text, options: [], range: range)
                .compactMap { $0.url?.absoluteString }
        }

        return results.map(trimTrailingPunctuation).filter { !$0.isEmpty }
    }

    private static func trimTrailingPunctuation(_ candidate: String) -> String {
        var value = candidate
        while let last = value.unicodeScalars.last, trailingPunctuation.contains(last) {
            value.removeLast()
        }
        return value
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
