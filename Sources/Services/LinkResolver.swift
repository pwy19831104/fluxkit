import Foundation

/// Turns whatever the user pasted into a concrete, downloadable media address.
///
/// Supported inputs:
/// 1. Direct file links (`.mp4`, `.mov`, `.webm`, ...) — used as-is.
/// 2. HLS playlists (`.m3u8`) — handed to the HLS downloader.
/// 3. HTML pages — inspected for `og:video`, `twitter:player:stream`, `<video>`,
///    `<source>` and JSON-LD `contentUrl` candidates.
/// 4. Client-rendered players (see `SiteExtractor`) — the page has no media element at
///    all, so the address is read from the site's own JSON endpoint instead.
struct LinkResolver {

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,video/*;q=0.8,*/*;q=0.7",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Entry point

    /// What a pasted link turns into: a single media file/stream, or a feed with episodes.
    enum ResolvedInput: Sendable {
        case media(ResolvedMedia)
        case podcast(PodcastFeed)
    }

    func resolve(input: String) async throws -> ResolvedMedia {
        switch try await resolveInput(input) {
        case .media(let media):
            return media
        case .podcast(let feed):
            // Callers that only understand single files get the newest episode.
            guard let newest = feed.episodes.first else { throw FeedParserError.noEpisodes }
            return newest.media(feed: feed)
        }
    }

    /// Resolves a pasted link, detecting podcast/Atom feeds as well as media.
    func resolveInput(_ input: String) async throws -> ResolvedInput {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResolveError.emptyInput }
        // Users paste entire share blurbs (“复制打开… https://… w@S.LJ”), not clean links.
        guard let link = Self.linkString(in: trimmed),
              let url = Self.normalizedURL(from: link) else { throw ResolveError.invalidURL }
        if let platform = Self.localizedPlatformName(for: url) {
            throw ResolveError.unsupportedPlatform(platform)
        }
        return try await resolveInput(url: url)
    }

    private func resolveInput(url: URL) async throws -> ResolvedInput {
        // Sites with a JavaScript player: the HTML is a skeleton, so skip straight to
        // their JSON endpoint.
        if let extraction = try await SiteExtractor.extract(from: url, session: session) {
            return .media(try await upgradedMedia(try await media(for: extraction, pageURL: url)))
        }

        let probe = try await probeURL(url)

        // A file or HLS playlist: nothing else to do.
        if Self.mediaKind(for: probe.contentType, url: probe.url) != nil {
            return .media(try await upgradedMedia(try await resolve(url: url, depth: 0)))
        }

        // Podcasts and other RSS/Atom feeds. Feeds can be large (years of episodes),
        // so they get a bigger read budget than normal pages.
        if FeedParser.looksLikeFeed(contentType: probe.contentType, url: probe.url) {
            let page = try await fetchText(probe.url)
            guard FeedParser.looksLikeFeedText(page.html) else {
                throw ResolveError.noMediaFound
            }
            return .podcast(try FeedParser.parse(text: page.html, feedURL: page.url))
        }

        return .media(try await upgradedMedia(try await resolve(url: url, depth: 0)))
    }

    /// Swaps an `http://` media address for its `https://` twin when the host supports it.
    private func upgradedMedia(_ media: ResolvedMedia) async throws -> ResolvedMedia {
        let secure = await upgradedToHTTPS(media.url)
        guard secure != media.url else { return media }
        var upgraded = media
        upgraded.url = secure
        return upgraded
    }

    /// The first web address inside a string, or `nil`. Kept here so the views and the
    /// share extension have one entry point.
    static func linkString(in text: String) -> String? {
        LinkTextExtractor.firstLink(in: text)
    }

    static func normalizedURL(from string: String) -> URL? {
        LinkURL.normalized(from: string)
    }

    /// Media URLs are frequently handed over as `http://` (搜狐's CDN does exactly that). Try the
    /// same address over TLS first: plaintext downloads are slower to trust and are the first thing
    /// App Transport Security blocks. Returns the original URL when the secure variant is not
    /// usable, so http-only hosts keep working.
    func upgradedToHTTPS(_ url: URL) async -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let secure = components?.url else { return url }

        var request = URLRequest(url: secure)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return url }
        // Any real HTTP answer proves the host speaks TLS for this path. 401/403/405/416 only mean
        // the server dislikes HEAD or the token, which is fine for our purpose.
        let usable = (200..<400).contains(http.statusCode)
            || [401, 403, 405, 416].contains(http.statusCode)
        if usable {
            #if DEBUG
            NSLog("RESOLVE: upgraded \(url.host ?? "?") to https")
            #endif
            return secure
        }
        return url
    }

    /// Media scraped from a page often only works with its page as `Referer`.
    static func refererHeaders(for pageURL: URL?) -> [String: String] {
        guard let pageURL else { return [:] }
        return ["Referer": pageURL.absoluteString]
    }

    // MARK: - Unsupported platforms

    /// Services that sign their media URLs and need a server-side extractor. Resolving them
    /// on-device is not possible (and bypassing their terms/DRM is out of scope), so fail fast
    /// with a clear message instead of downloading an HTML page and giving up.
    private static let unsupportedPlatforms: [(suffix: String, english: String, chinese: String)] = [
        ("douyin.com", "Douyin", "抖音"),
        ("iesdouyin.com", "Douyin", "抖音"),
        ("tiktok.com", "TikTok", "TikTok"),
        ("youtube.com", "YouTube", "YouTube"),
        ("youtu.be", "YouTube", "YouTube"),
        ("instagram.com", "Instagram", "Instagram"),
        ("facebook.com", "Facebook", "Facebook"),
        ("fb.watch", "Facebook", "Facebook"),
        ("twitter.com", "X", "X"),
        ("x.com", "X", "X"),
        ("kuaishou.com", "Kuaishou", "快手"),
        ("xiaohongshu.com", "Xiaohongshu", "小红书"),
        ("xhslink.com", "Xiaohongshu", "小红书"),
        ("bilibili.com", "Bilibili", "哔哩哔哩"),
        ("b23.tv", "Bilibili", "哔哩哔哩"),
        ("netflix.com", "Netflix", "Netflix"),
        // Chinese VOD platforms verified against their live pages: the watch page carries no media
        // address, and the player asks a signed, session-bound endpoint for it.
        // 乐视 (le.com) is the clearest case: `player-pc.le.com/player/playJson.json` answers
        // `{"code":403,"message":"无sign参数"}` and only serves paywalled titles anyway.
        ("le.com", "LeTV", "乐视视频"),
        ("letv.com", "LeTV", "乐视视频"),
        ("iqiyi.com", "iQIYI", "爱奇艺"),
        ("iq.com", "iQIYI", "爱奇艺"),
        ("v.qq.com", "Tencent Video", "腾讯视频"),
        ("youku.com", "Youku", "优酷"),
        ("tudou.com", "Youku", "优酷"),
        ("mgtv.com", "Mango TV", "芒果TV"),
        ("miguvideo.com", "Migu Video", "咪咕视频"),
        // 央视频's player is a closed WASM/HLS stack (CMG player) served by 总台.
        ("yangshipin.cn", "Yangshipin", "央视频")
    ]

    /// - Returns: the English display name of the platform, or `nil` when the host is fine.
    static func unsupportedPlatform(for url: URL) -> String? {
        platformEntry(for: url)?.english
    }

    /// Same, in the language the UI is currently in.
    static func localizedPlatformName(for url: URL, language: AppLanguage = .current) -> String? {
        guard let entry = platformEntry(for: url) else { return nil }
        return L(entry.english, entry.chinese, language: language)
    }

    private static func platformEntry(for url: URL) -> (suffix: String, english: String, chinese: String)? {
        guard let host = url.host?.lowercased() else { return nil }
        return unsupportedPlatforms.first { host == $0.suffix || host.hasSuffix("." + $0.suffix) }
    }

    // MARK: - Resolution

    private func resolve(url: URL, depth: Int) async throws -> ResolvedMedia {
        guard depth <= 2 else { throw ResolveError.noMediaFound }

        let probe = try await probeURL(url)

        if let kind = Self.mediaKind(for: probe.contentType, url: probe.url) {
            return ResolvedMedia(
                kind: kind,
                url: probe.url,
                title: nil,
                mimeType: probe.contentType,
                contentLength: kind == .hls ? nil : probe.contentLength,
                pageURL: depth == 0 ? url : nil
            )
        }

        guard Self.isHTML(probe.contentType) else {
            throw ResolveError.noMediaFound
        }

        let page = try await fetchPage(probe.url)
        let html = page.html

        guard let candidate = Self.firstMediaCandidate(in: html, base: page.url) else {
            throw ResolveError.noMediaFound
        }

        // Candidate may itself be an HTML page (player page inside the page).
        let candidateProbe = try? await probeURL(candidate)
        if let candidateProbe,
           let kind = Self.mediaKind(for: candidateProbe.contentType, url: candidateProbe.url) {
            return ResolvedMedia(
                kind: kind,
                url: candidateProbe.url,
                title: Self.pageTitle(in: html) ?? Self.title(from: candidateProbe.url),
                mimeType: candidateProbe.contentType,
                contentLength: kind == .hls ? nil : candidateProbe.contentLength,
                thumbnailURL: Self.thumbnailURL(in: html, base: page.url),
                pageURL: probe.url,
                httpHeaders: Self.refererHeaders(for: probe.url)
            )
        }

        if let candidateProbe, Self.isHTML(candidateProbe.contentType) {
            return try await resolve(url: candidateProbe.url, depth: depth + 1)
        }

        // Last resort: treat the candidate as a plain media file (or a playlist).
        let fallbackKind: MediaKind = Self.looksLikePlaylist(candidate) ? .hls : .progressive
        return ResolvedMedia(
            kind: fallbackKind,
            url: candidate,
            title: Self.pageTitle(in: html) ?? Self.title(from: candidate),
            mimeType: candidateProbe?.contentType ?? (fallbackKind == .hls ? "application/vnd.apple.mpegurl" : nil),
            contentLength: candidateProbe?.contentLength,
            thumbnailURL: Self.thumbnailURL(in: html, base: page.url),
            pageURL: probe.url,
            httpHeaders: Self.refererHeaders(for: probe.url)
        )
    }

    /// Wraps an address handed over by a `SiteExtractor` the way the scraper does:
    /// probe for the real content type/size and keep the page as `Referer`.
    private func media(for extraction: SiteExtractor.Extraction, pageURL: URL) async throws -> ResolvedMedia {
        let probe = try? await probeURL(extraction.url)
        let resolvedURL = probe?.url ?? extraction.url
        let contentType = extraction.mimeType ?? probe?.contentType
        let kind = Self.mediaKind(for: contentType, url: resolvedURL)
            ?? (Self.looksLikePlaylist(resolvedURL) ? .hls : .progressive)
        return ResolvedMedia(
            kind: kind,
            url: resolvedURL,
            title: extraction.title ?? Self.title(from: resolvedURL),
            mimeType: contentType,
            contentLength: kind == .hls ? nil : (extraction.contentLength ?? probe?.contentLength),
            thumbnailURL: extraction.thumbnailURL,
            pageURL: pageURL,
            httpHeaders: Self.refererHeaders(for: pageURL)
        )
    }

    // MARK: - Probing

    private struct Probe {
        var url: URL
        var contentType: String?
        var contentLength: Int64?
    }

    private struct Page {
        var url: URL
        var html: String
    }

    private func probeURL(_ url: URL) async throws -> Probe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200..<400).contains(http.statusCode) || http.statusCode == 416 {
                return Probe(
                    url: response.url ?? url,
                    contentType: http.value(forHTTPHeaderField: "Content-Type"),
                    contentLength: http.expectedContentLength > 0 ? http.expectedContentLength : nil
                )
            }
        } catch {
            // Fall through to GET with a range request.
        }

        var getRequest = URLRequest(url: url)
        getRequest.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        do {
            let (data, response) = try await session.data(for: getRequest)
            guard let http = response as? HTTPURLResponse else {
                throw ResolveError.network("Unexpected response")
            }
            guard (200..<400).contains(http.statusCode) else {
                throw ResolveError.network("HTTP \(http.statusCode)")
            }
            var length = http.expectedContentLength > 0 ? http.expectedContentLength : nil
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last, let value = Int64(total) {
                length = value
            }
            let type = http.value(forHTTPHeaderField: "Content-Type")
            if Self.isHTML(type), let text = String(data: data, encoding: .utf8),
               Self.looksLikePlaylistText(text) {
                return Probe(url: response.url ?? url, contentType: "application/vnd.apple.mpegurl", contentLength: nil)
            }
            return Probe(url: response.url ?? url, contentType: type, contentLength: length)
        } catch let error as ResolveError {
            throw error
        } catch {
            throw ResolveError.network(error.localizedDescription)
        }
    }

    /// Reads a whole feed document (podcast feeds routinely exceed 10 MB).
    private func fetchText(_ url: URL) async throws -> Page {
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ResolveError.network("Could not load that feed.")
        }
        return Page(url: response.url ?? url, html: Self.decodedText(from: data))
    }

    private func fetchPage(_ url: URL) async throws -> Page {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ResolveError.network("Could not load that page.")
        }
        return Page(url: response.url ?? url, html: Self.decodedText(from: data, limit: 4_000_000))
    }

    /// Many Chinese sites (搜狐视频 among them) still serve GBK/GB18030. Decoding such a page as
    /// UTF-8 fails and used to yield an empty string, which looks exactly like "this page has no
    /// video" — so fall back instead of giving up.
    ///
    /// `limit` is for HTML pages only. Feeds must be decoded whole: cutting an XML document in the
    /// middle makes `XMLParser` fail, which reads as "that isn't a podcast feed" (Syntax.fm ships
    /// ~10 MB, The Daily ~20 MB).
    static func decodedText(from data: Data, limit: Int? = nil) -> String {
        let slice: Data = limit.map { data.prefix($0) } ?? data
        if let text = String(data: slice, encoding: .utf8) { return text }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: slice, encoding: gb18030) { return text }
        return String(data: slice, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Type helpers

    static func isHTML(_ contentType: String?) -> Bool {
        guard let type = contentType?.lowercased() else { return false }
        return type.contains("text/html") || type.contains("application/xhtml")
    }

    static func looksLikePlaylist(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
    }

    static func looksLikePlaylistText(_ text: String) -> Bool {
        let head = text.prefix(4096)
        return head.contains("#EXTM3U")
    }

    static func mediaKind(for contentType: String?, url: URL) -> MediaKind? {
        let type = contentType?.lowercased() ?? ""
        if type.contains("mpegurl") || type.contains("m3u") { return .hls }
        if type.hasPrefix("video/") || type.hasPrefix("audio/") {
            if type.contains("mp2t") { return .hls }
            return .progressive
        }
        if type.contains("octet-stream") || type.isEmpty {
            if LooksLike.mediaExtension(url) {
                return LooksLike.playlistExtension(url) ? .hls : .progressive
            }
            return nil
        }
        if LooksLike.mediaExtension(url) {
            return LooksLike.playlistExtension(url) ? .hls : .progressive
        }
        return nil
    }

    enum LooksLike {
        static func playlistExtension(_ url: URL) -> Bool {
            url.pathExtension.lowercased() == "m3u8"
        }

        static func mediaExtension(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ResolvedMedia.mediaExtensions.contains(ext) || ext == "m3u8"
        }
    }

    // MARK: - HTML scraping

    static func firstMediaCandidate(in html: String, base: URL) -> URL? {
        for raw in rawCandidates(in: html) {
            let cleaned = raw
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  !cleaned.hasPrefix("blob:"),
                  !cleaned.hasPrefix("data:"),
                  !cleaned.hasPrefix("#"),
                  !cleaned.hasPrefix("javascript:") else { continue }
            guard let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            return url
        }
        return nil
    }

    private static func rawCandidates(in html: String) -> [String] {
        var results: [String] = []

        // 1. Meta tags with media semantics.
        let metaPriority = [
            "og:video:secure_url", "og:video:url", "og:video",
            "twitter:player:stream", "contenturl", "video"
        ]
        let metaTags = matches(pattern: "<meta\\b[^>]*>", in: html)
        var metaValues: [String: [String]] = [:]
        for tag in metaTags {
            let attrs = attributes(in: tag)
            let key = (attrs["property"] ?? attrs["name"] ?? attrs["itemprop"] ?? "").lowercased()
            guard !key.isEmpty, let content = attrs["content"], !content.isEmpty else { continue }
            metaValues[key, default: []].append(content)
        }
        for key in metaPriority {
            if let values = metaValues[key] { results.append(contentsOf: values) }
        }
        // 1b. <link rel="..."> variants some sites use.
        for tag in matches(pattern: "<link\\b[^>]*>", in: html) {
            let attrs = attributes(in: tag)
            if let type = attrs["type"]?.lowercased(), type.hasPrefix("video/"), let href = attrs["href"] {
                results.append(href)
            }
        }

        // 2. <video src> and <source src>.
        for tag in matches(pattern: "<video\\b[^>]*>", in: html) {
            if let src = attributes(in: tag)["src"] { results.append(src) }
        }
        for tag in matches(pattern: "<source\\b[^>]*>", in: html) {
            if let src = attributes(in: tag)["src"] { results.append(src) }
        }

        // 3. JSON-LD / inline JSON.
        for pattern in ["\"contentUrl\"\\s*:\\s*\"([^\"]+)\"",
                        "\"videoUrl\"\\s*:\\s*\"([^\"]+)\"",
                        "\"playlistUrl\"\\s*:\\s*\"([^\"]+)\"",
                        // Baidu-family feed payloads (`window.jsonData`) that `SiteExtractor`
                        // does not claim, e.g. m.baidu.com.
                        "\"playurl\"\\s*:\\s*\"([^\"]+)\""] {
            for match in matches(pattern: pattern, in: html, group: 1) {
                results.append(match)
            }
        }

        // 4. Bare media links inside inline scripts.
        for match in matches(pattern: "https?://[^\"'\\s<>]+?\\.m3u8[^\"'\\s<>]*", in: html) {
            results.append(match)
        }

        // Deduplicate while preserving order.
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }

    static func pageTitle(in html: String) -> String? {
        if let value = matches(pattern: "<meta[^>]+(?:property|name)=[\"']og:title[\"'][^>]*content=[\"']([^\"']+)[\"']", in: html, group: 1).first,
           !value.isEmpty {
            return decodeEntities(value)
        }
        if let value = matches(pattern: "<title[^>]*>([^<]+)</title>", in: html, group: 1).first {
            let cleaned = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    static func thumbnailURL(in html: String, base: URL) -> URL? {
        guard let raw = matches(pattern: "<meta[^>]+(?:property|name)=[\"']og:image(?::secure_url|:url)?[\"'][^>]*content=[\"']([^\"']+)[\"']", in: html, group: 1).first else {
            return nil
        }
        let cleaned = decodeEntities(raw).replacingOccurrences(of: "\\/", with: "/")
        return URL(string: cleaned, relativeTo: base)?.absoluteURL
    }

    static func title(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return name.isEmpty ? nil : name
    }

    static func decodeEntities(_ value: String) -> String {
        var text = value
        let map = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
        for (key, replacement) in map {
            text = text.replacingOccurrences(of: key, with: replacement)
        }
        return text
    }

    // MARK: - Regex helpers

    private static func matches(pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))",
                                                   options: []) else { return result }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let key = String(tag[keyRange]).lowercased()
            for index in 2...4 where match.range(at: index).location != NSNotFound {
                if let valueRange = Range(match.range(at: index), in: tag) {
                    result[key] = String(tag[valueRange])
                    break
                }
            }
        }
        return result
    }
}
