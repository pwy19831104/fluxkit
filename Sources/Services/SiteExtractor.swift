import Foundation

/// Media sites whose player address is *not* in the HTML.
///
/// A few large sites ship a client-rendered player: the server sends a skeleton page
/// (`ssr-skeleton` placeholders) and the real `<video class="art-video" src="…">` element
/// is injected after hydration, together with a freshly signed, short-lived address.
/// Scraping that HTML can never work — there is nothing to scrape.
///
/// Their own player is not special either: it reads the same address from a plain JSON
/// endpoint. So each such site gets a small extractor that asks that endpoint directly
/// and returns the address it would have put in the `<video>` tag. Unknown hosts get
/// `nil` and keep using the generic `LinkResolver` scraper.
enum SiteExtractor {

    /// What an extractor found. `contentLength` stays `nil` when the endpoint already
    /// reports it, so `LinkResolver` does not have to spend a `HEAD` on the media URL.
    struct Extraction: Sendable {
        var url: URL
        var title: String?
        var thumbnailURL: URL?
        var mimeType: String?
        var contentLength: Int64?
    }

    /// - Returns: the extracted media, or `nil` when `url` is not a known site.
    /// - Throws: when the host *is* known but no playable address came back.
    static func extract(from url: URL, session: URLSession) async throws -> Extraction? {
        guard let host = url.host?.lowercased() else { return nil }
        if matches(host, Haokan.hosts) {
            return try await Haokan.extract(from: url, session: session)
        }
        return nil
    }

    // MARK: - Host matching

    static func matches(_ host: String, _ suffixes: [String]) -> Bool {
        suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: - JSON helpers

    /// Only absolute http(s) addresses are download candidates; `blob:`/`data:` aren't.
    static func httpURL(_ raw: String) -> URL? {
        let cleaned = raw
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Reads a JSON body, refusing anything that is not a JSON object (anti-bot HTML,
    /// redirect pages, …).
    static func fetchJSON(_ url: URL, referer: URL?, session: URLSession) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ResolveError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ResolveError.network("HTTP \(http.statusCode)")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data.prefix(4_000_000)),
              let root = object as? [String: Any] else {
            throw ResolveError.noMediaFound
        }
        return root
    }

    // MARK: - haokan.baidu.com

    /// 好看视频. `GET /v?vid=<vid>` is the watch page; adding `_format=json` makes the
    /// same route answer with the payload the player hydrates the page with, including
    /// `data.apiData.curVideoMeta.clarityUrl[*].url` — the very address a user sees on
    /// the page's `<video class="art-video" src="…">` element.
    enum Haokan {
        static let hosts = ["haokan.baidu.com"]

        /// Video ids are long digit strings; they appear as `?vid=` or as the last
        /// path component of `/v/<id>` and `/video/<id>` links.
        static func videoID(in url: URL) -> String? {
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name.lowercased() == "vid" })?
                .value,
               isValidID(value) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for part in url.pathComponents.reversed() where isValidID(part) {
                return part.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        private static func isValidID(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // `vid` is a 15–25 digit number; require digits only so a path such as
            // `/v/1234` (a category page) is not mistaken for a video.
            return trimmed.count >= 10 && trimmed.allSatisfy(\.isNumber)
        }

        static func endpoint(for pageURL: URL, videoID: String) -> URL {
            var components = URLComponents()
            components.scheme = pageURL.scheme ?? "https"
            components.host = pageURL.host ?? "haokan.baidu.com"
            components.path = "/v"
            components.queryItems = [
                URLQueryItem(name: "vid", value: videoID),
                URLQueryItem(name: "_format", value: "json")
            ]
            if let url = components.url { return url }
            return URL(string: "https://haokan.baidu.com/v?vid=\(videoID)&_format=json")!
        }

        static func extract(from pageURL: URL, session: URLSession) async throws -> Extraction {
            guard let videoID = videoID(in: pageURL) else { throw ResolveError.noMediaFound }
            let root = try await fetchJSON(endpoint(for: pageURL, videoID: videoID),
                                           referer: pageURL,
                                           session: session)
            return try extraction(fromJSONObject: root)
        }

        /// Separated from the network call so it can be unit-tested with a fixture.
        static func extraction(fromJSONObject root: [String: Any]) throws -> Extraction {
            // `errno` 30020 = 视频不存在 / video removed; other codes mean the same to us.
            if let errno = (root["errno"] as? NSNumber)?.intValue, errno != 0 {
                throw ResolveError.noMediaFound
            }
            guard let data = root["data"] as? [String: Any],
                  let apiData = data["apiData"] as? [String: Any],
                  let meta = apiData["curVideoMeta"] as? [String: Any],
                  let url = playURL(in: meta) else {
                throw ResolveError.noMediaFound
            }
            return Extraction(
                url: url,
                title: cleanedTitle(meta["title"] as? String),
                thumbnailURL: (meta["poster"] as? String).flatMap { poster in
                    // The poster is served over http; the app is https/ATS only.
                    SiteExtractor.httpURL(poster.replacingOccurrences(of: "http://", with: "https://"))
                }
            )
        }

        /// `clarityUrl` lists every rendition with its size in MB (标清 / 高清 / 超清 …).
        /// The biggest one is the best the site is willing to hand out; `playurl` and
        /// `previewUrlHttp` are the plain and the watermarked fallbacks.
        static func playURL(in meta: [String: Any]) -> URL? {
            let renditions = (meta["clarityUrl"] as? [[String: Any]]) ?? []
            let ranked = renditions.compactMap { entry -> (url: URL, megabytes: Double)? in
                guard let raw = entry["url"] as? String,
                      let url = SiteExtractor.httpURL(raw) else { return nil }
                return (url, (entry["videoSize"] as? NSNumber)?.doubleValue ?? 0)
            }
            if let best = ranked.max(by: { $0.megabytes < $1.megabytes }) {
                return best.url
            }
            for key in ["playurl", "previewUrlHttp"] {
                if let raw = meta[key] as? String, let url = SiteExtractor.httpURL(raw) {
                    return url
                }
            }
            return nil
        }

        private static func cleanedTitle(_ raw: String?) -> String? {
            guard let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cleaned.isEmpty else { return nil }
            return cleaned
        }
    }
}
