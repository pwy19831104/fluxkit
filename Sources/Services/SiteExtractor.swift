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
        if matches(host, Sohu.hosts) {
            return try await Sohu.extract(from: url, session: session)
        }
        if matches(host, Baidu.hosts) {
            return try await Baidu.extract(from: url, session: session)
        }
        if matches(host, Reddit.hosts) {
            return try await Reddit.extract(from: url, session: session)
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
        let value = try await fetchJSONValue(url, referer: referer, session: session)
        guard let object = value as? [String: Any] else { throw ResolveError.noMediaFound }
        return object
    }

    /// Same as `fetchJSON` but for endpoints that answer with a list (Reddit's `/comments/<id>.json`
    /// returns `[post, comments]`).
    static func fetchJSONValue(_ url: URL, referer: URL?, session: URLSession) async throws -> Any {
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

        guard let value = try? JSONSerialization.jsonObject(with: data.prefix(4_000_000)) else {
            throw ResolveError.noMediaFound
        }
        return value
    }

    /// Reads a whole document as text (watch pages whose player id has to be scraped).
    static func fetchText(_ url: URL, referer: URL?, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
        return LinkResolver.decodedText(from: data, limit: 4_000_000)
    }
    /// First capture group of `pattern`, or `nil`.
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// `clarityUrl` lists every rendition with its size in MB (标清 / 高清 / 超清 …). The biggest
    /// one is the best the site is willing to hand out; `playurl` and `previewUrlHttp` are the
    /// plain and the watermarked fallbacks. Both 好看视频 and 百度信息流 use this shape.
    static func bestRenditionURL(in meta: [String: Any],
                                 renditionKeys: [String] = ["clarityUrl", "clarityArr"],
                                 fallbackKeys: [String] = ["playurl", "play_url", "previewUrlHttp"]) -> URL? {
        var renditions: [[String: Any]] = []
        for key in renditionKeys {
            if let list = meta[key] as? [[String: Any]] { renditions.append(contentsOf: list) }
        }
        let ranked = renditions.compactMap { entry -> (url: URL, megabytes: Double)? in
            guard let raw = entry["url"] as? String,
                  let url = httpURL(raw) else { return nil }
            return (url, (entry["videoSize"] as? NSNumber)?.doubleValue ?? 0)
        }
        if let best = ranked.max(by: { $0.megabytes < $1.megabytes }) {
            return best.url
        }
        for key in fallbackKeys {
            if let raw = meta[key] as? String, let url = httpURL(raw) {
                return url
            }
        }
        return nil
    }

    /// The JSON object starting at the first `{` after `marker` (`"curVideoMeta"`, say), matched by
    /// braces and aware of string literals, so it can be lifted out of an HTML document.
    static func jsonObjectSlice(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        var index = markerRange.upperBound
        var sawColon = false
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if character == ":", !sawColon {
                sawColon = true
                index = text.index(after: index)
                continue
            }
            // Anything but `{` right after the colon (`null`, `0`, …) means there is no object.
            guard character == "{", sawColon else { return nil }
            break
        }
        guard index < text.endIndex else { return nil }

        let start = index
        var depth = 0
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return nil
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
                  let url = bestRenditionURL(in: meta) else {
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

        private static func cleanedTitle(_ raw: String?) -> String? {
            guard let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cleaned.isEmpty else { return nil }
            return cleaned
        }
    }

    // MARK: - tv.sohu.com

    /// 搜狐视频. The watch page is server-rendered but its URL is base64 (`/v/MjAyNjExMDQv…`),
    /// so the numeric id has to come out of the HTML — it is there as `var vid="10760370"`: the
    /// page never contains a media address. The player then asks
    /// `GET https://my.tv.sohu.com/play/videonew.do?vid=<vid>` and reads
    /// `data.mp4PlayUrl[0]`, a tokenised URL that 302-redirects to the real `.mp4` on the
    /// itc.cn CDN. Verified 2026-11: the redirect chain serves `206 video/mp4` with the size in
    /// `Content-Range`, and the token lapses within minutes (hence the download-manager refresh).
    enum Sohu {
        /// `tv.sohu.com` only: plain `www.sohu.com` news pages expose `og:video` and belong to
        /// the generic scraper.
        static let hosts = ["tv.sohu.com"]

        static func videoID(inHTML html: String) -> String? {
            firstMatch(#"var\s+vid\s*=\s*"(\d{5,})""#, in: html)
        }

        static func endpoint(videoID: String, pageURL: URL) -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "my.tv.sohu.com"
            components.path = "/play/videonew.do"
            components.queryItems = [
                URLQueryItem(name: "vid", value: videoID),
                URLQueryItem(name: "referer", value: pageURL.absoluteString)
            ]
            if let url = components.url { return url }
            return URL(string: "https://my.tv.sohu.com/play/videonew.do?vid=\(videoID)")!
        }

        static func extract(from pageURL: URL, session: URLSession) async throws -> Extraction {
            let html = try await fetchText(pageURL, referer: nil, session: session)
            guard let videoID = videoID(inHTML: html) else { throw ResolveError.noMediaFound }

            let root = try await fetchJSON(endpoint(videoID: videoID, pageURL: pageURL),
                                           referer: pageURL,
                                           session: session)
            return try extraction(fromJSONObject: root)
        }

        /// Separated from the network calls so it can be unit-tested with a fixture.
        static func extraction(fromJSONObject root: [String: Any]) throws -> Extraction {
            guard let data = root["data"] as? [String: Any] else { throw ResolveError.noMediaFound }

            // `play` is 0 for videos the visitor may not watch; `pay_data` is filled in for
            // VIP-only episodes. Both are worth a clearer message than "no video found".
            if let play = (root["play"] as? NSNumber)?.intValue, play == 0 {
                throw ResolveError.protectedStream(
                    L("This 搜狐视频 episode is for VIP members, so there is no downloadable file. Try a free video instead.",
                      "这个搜狐视频节目需要会员，没有可直接下载的文件。换一个免费视频试试。")
                )
            }
            if let payData = (root["pay_data"] as? [String: Any]) ?? (data["pay_data"] as? [String: Any]),
               !payData.isEmpty {
                throw ResolveError.protectedStream(
                    L("This 搜狐视频 episode is for VIP members, so there is no downloadable file. Try a free video instead.",
                      "这个搜狐视频节目需要会员，没有可直接下载的文件。换一个免费视频试试。")
                )
            }

            let candidates = (data["mp4PlayUrl"] as? [String]) ?? []
            guard let raw = candidates.compactMap(httpURL).first else {
                // `clipsURL` is the HLS rendition list when the site has no progressive file.
                let clips = (data["clipsURL"] as? [String]) ?? []
                guard let playlist = clips.compactMap(httpURL).first else { throw ResolveError.noMediaFound }
                return Extraction(url: playlist, title: cleanedTitle(data["tvName"] as? String),
                                  mimeType: "application/vnd.apple.mpegurl")
            }

            let size = (data["totalBytes"] as? NSNumber)?.int64Value
            let cover = (data["coverImg"] as? String).flatMap(httpURL)
            return Extraction(
                url: raw,
                title: cleanedTitle(data["tvName"] as? String),
                thumbnailURL: cover,
                contentLength: size
            )
        }

        private static func cleanedTitle(_ raw: String?) -> String? {
            guard let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !cleaned.isEmpty else { return nil }
            return cleaned
        }
    }

    // MARK: - mbd.baidu.com

    /// 百度信息流视频落地页 (`/newspage/data/videolanding?nid=sv_…`). No second request is needed:
    /// the shell carries `window.jsonData` inline, whose `curVideoMeta` has the same
    /// `clarityUrl` shape 好看视频 uses — and, unlike haokan, the `vd*.bdstatic.com` addresses
    /// there are plain and unsigned, so they can be downloaded as-is.
    enum Baidu {
        static let hosts = ["mbd.baidu.com"]

        static func extract(from pageURL: URL, session: URLSession) async throws -> Extraction {
            let html = try await fetchText(pageURL, referer: nil, session: session)
            return try extraction(fromHTML: html)
        }

        /// Baidu serves two payload shapes for the same link, apparently at random:
        /// 1. a ~7 KB shell whose `window.jsonData` has `curVideoMeta` (`clarityUrl`, `playurl`);
        /// 2. a ~19 KB shell whose `window.jsonData` is `{"errno":"0","data":{…"videoInfo":{…}}}`
        ///    (`clarityArr`, `play_url`, `posterImage`).
        /// Both are handled so the extractor does not depend on which one comes back.
        static func extraction(fromHTML html: String) throws -> Extraction {
            for (marker, posterKey) in [("\"curVideoMeta\"", "poster"), ("\"videoInfo\"", "posterImage")] {
                guard let slice = jsonObjectSlice(after: marker, in: html),
                      let data = slice.data(using: .utf8),
                      let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let url = bestRenditionURL(in: meta) else { continue }
                let title = (meta["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return Extraction(
                    url: secure(url),
                    title: title?.isEmpty == false ? title : nil,
                    thumbnailURL: (meta[posterKey] as? String).flatMap { httpURL($0) }.map(secure)
                )
            }
            throw ResolveError.noMediaFound
        }

        /// The landing page hands out `http://vd*.bdstatic.com/…` addresses; the CDN speaks https.
        private static func secure(_ url: URL) -> URL {
            guard url.scheme?.lowercased() == "http",
                  let host = url.host?.lowercased(),
                  host.hasSuffix("bdstatic.com") else { return url }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            return components?.url ?? url
        }
    }

    // MARK: - reddit.com

    /// A Reddit video post keeps its streams in the post's own JSON
    /// (`/comments/<id>.json`), under `secure_media.reddit_video` (or `media` for older posts).
    ///
    /// `hls_url` is the one worth downloading: Reddit keeps audio in a **separate rendition**, and
    /// `HLSDownloader` already merges `#EXT-X-MEDIA:TYPE=AUDIO` back into the exported file.
    /// `fallback_url` is the DASH video track on its own — no audio — so it is only used when the
    /// post offers no HLS at all, and the caller is told what it is getting.
    enum Reddit {
        static let hosts = ["reddit.com", "redd.it"]

        /// The post id: `/r/<sub>/comments/<id>/<slug>` or a `redd.it/<id>` short link.
        static func postID(in url: URL) -> String? {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let index = parts.firstIndex(of: "comments"), index + 1 < parts.count {
                let id = parts[index + 1]
                return isPostID(id) ? id : nil
            }
            if url.host?.lowercased().hasSuffix("redd.it") == true, let id = parts.first {
                return isPostID(id) ? id : nil
            }
            return nil
        }

        private static func isPostID(_ value: String) -> Bool {
            value.count >= 5 && value.count <= 8 && value.allSatisfy { $0.isLetter || $0.isNumber }
        }

        static func endpoint(for url: URL, postID: String) -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.reddit.com"
            components.path = "/comments/\(postID).json"
            components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
            if let url = components.url { return url }
            return URL(string: "https://www.reddit.com/comments/\(postID).json")!
        }

        static func extract(from pageURL: URL, session: URLSession) async throws -> Extraction {
            guard let postID = postID(in: pageURL) else { throw ResolveError.noMediaFound }
            let payload = try await fetchJSONValue(endpoint(for: pageURL, postID: postID),
                                                   referer: pageURL,
                                                   session: session)
            return try extraction(fromJSONValue: payload)
        }

        /// Separated from the network call so it can be unit-tested with a fixture.
        static func extraction(fromJSONValue value: Any) throws -> Extraction {
            guard let listing = value as? [Any],
                  let first = listing.first as? [String: Any],
                  let data = first["data"] as? [String: Any],
                  let children = data["children"] as? [[String: Any]],
                  let post = children.first?["data"] as? [String: Any] else {
                throw ResolveError.noMediaFound
            }

            let video = (post["secure_media"] as? [String: Any])?["reddit_video"] as? [String: Any]
                ?? (post["media"] as? [String: Any])?["reddit_video"] as? [String: Any]
                ?? (post["preview"] as? [String: Any])?["reddit_video_preview"] as? [String: Any]
            guard let video else { throw ResolveError.noMediaFound }

            let title = (post["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTitle = title?.isEmpty == false ? title : nil

            if let raw = video["hls_url"] as? String, let hls = httpURL(raw) {
                return Extraction(url: hls, title: cleanTitle,
                                  mimeType: "application/vnd.apple.mpegurl")
            }
            if let raw = video["fallback_url"] as? String, let fallback = httpURL(raw) {
                // Video-only: DASH keeps the audio track elsewhere.
                return Extraction(url: fallback, title: cleanTitle)
            }
            throw ResolveError.noMediaFound
        }
    }
}
