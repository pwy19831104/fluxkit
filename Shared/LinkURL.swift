import Foundation

/// Turns user-entered text into an `http(s)` URL. Shared by the app and the share extension
/// so both accept exactly the same inputs.
enum LinkURL {

    /// - Accepts `https://host/path`, `http://…`, and bare `host/path` (with or without a port).
    /// - Rejects everything that is not web: by scheme (`ftp:`, `file:`, `mailto:`, …) or shape.
    static func normalized(from string: String) -> URL? {
        var candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if let scheme = uriScheme(of: candidate) {
            let lowered = scheme.lowercased()
            guard lowered == "http" || lowered == "https",
                  candidate.hasPrefix(scheme + "://") else { return nil }
        } else {
            // A bare domain must be a single token: "not a url" is not a link.
            guard candidate.contains("."),
                  candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
            candidate = "https://" + candidate
        }

        guard var comps = URLComponents(string: candidate),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              comps.host?.isEmpty == false else { return nil }
        if comps.path.isEmpty { comps.path = "/" }
        return comps.url
    }

    /// The `scheme` part of `scheme:…`, but only when the colon really starts a URI scheme.
    /// A dot before the colon means it is a host, as in `example.com:8080/clip.mp4`.
    private static func uriScheme(of string: String) -> String? {
        guard let colon = string.firstIndex(of: ":") else { return nil }
        let head = string[..<colon]
        guard let first = head.first, first.isLetter,
              !head.contains("."),
              head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }
        return String(head)
    }
}
