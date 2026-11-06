import Foundation
import Observation

/// Subscribed podcast feeds, cached episode metadata, and refresh logic.
@MainActor
@Observable
final class PodcastStore {

    static let shared = PodcastStore()

    /// How many episodes are cached per subscription. Feeds can hold thousands; the store keeps a
    /// window and the UI says so, instead of silently showing a shorter list.
    static let maxStoredEpisodes = 100

    private(set) var feeds: [PodcastFeed] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// Set when `podcasts.json` could not be used (see `PersistedIndex`).
    private(set) var persistenceWarning: String?
    private var canSave = true

    private let fileURL = AppPaths.root.appendingPathComponent("podcasts.json")
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": LinkResolver.userAgent]
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        load()
    }

    // MARK: - Queries

    var sortedFeeds: [PodcastFeed] {
        feeds.sorted { lhs, rhs in
            let left = lhs.episodes.first?.publishedAt ?? .distantPast
            let right = rhs.episodes.first?.publishedAt ?? .distantPast
            return left > right
        }
    }

    /// Identity used for subscription de-duplication: `…/rss` and `…/rss/` are the same feed, and
    /// so is the URL a redirect landed on.
    nonisolated static func feedKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if let path = components.path as String?, path.count > 1, path.hasSuffix("/") {
            components.path = String(path.dropLast())
        }
        // Analytics parameters must not fork a subscription; real feed parameters stay. An empty
        // list is set to `nil` so the URL does not keep a dangling "?".
        let meaningful = components.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") }
        components.queryItems = (meaningful?.isEmpty ?? true) ? nil : meaningful
        return components.url?.absoluteString ?? url.absoluteString
    }

    func isSubscribed(_ feedURL: URL) -> Bool {
        let key = Self.feedKey(feedURL)
        return feeds.contains { Self.feedKey($0.feedURL) == key }
    }

    func feed(withURL url: URL) -> PodcastFeed? {
        let key = Self.feedKey(url)
        return feeds.first { Self.feedKey($0.feedURL) == key }
    }

    // MARK: - Mutations

    func subscribe(_ feed: PodcastFeed, autoDownload: Int? = nil) {
        var snapshot = feed
        snapshot.episodes = Array(feed.episodes.prefix(Self.maxStoredEpisodes))
        if let index = feeds.firstIndex(where: { Self.feedKey($0.feedURL) == Self.feedKey(feed.feedURL) }) {
            feeds[index] = snapshot
        } else {
            feeds.append(snapshot)
        }
        save()
        let count = ProEntitlements.effectiveAutoDownload(
            configured: autoDownload ?? AppSettings.shared.podcastAutoDownload,
            isPro: ProStore.shared.isPro
        )
        if count > 0 {
            downloadLatest(count, from: snapshot)
        }
    }

    func unsubscribe(_ feedURL: URL) {
        let key = Self.feedKey(feedURL)
        feeds.removeAll { Self.feedKey($0.feedURL) == key }
        save()
    }

    func apply(_ feed: PodcastFeed) {
        let key = Self.feedKey(feed.feedURL)
        guard let index = feeds.firstIndex(where: { Self.feedKey($0.feedURL) == key }) else { return }
        var snapshot = feed
        snapshot.episodes = Array(feed.episodes.prefix(Self.maxStoredEpisodes))
        feeds[index] = snapshot
        save()
    }

    // MARK: - Refresh

    @discardableResult
    func refresh(_ feed: PodcastFeed) async -> PodcastFeed? {
        do {
            let refreshed = try await fetchFeed(feed.feedURL)
            apply(refreshed)
            return refreshed
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        for feed in feeds {
            guard let refreshed = await refresh(feed) else { continue }
            let count = ProEntitlements.effectiveAutoDownload(
                configured: AppSettings.shared.podcastAutoDownload,
                isPro: ProStore.shared.isPro
            )
            if count > 0 {
                downloadLatest(count, from: refreshed)
            }
        }
    }

    /// Resolves a pasted feed URL and adds it to the subscriptions.
    func addFeed(from input: String) async throws -> PodcastFeed {
        guard let link = LinkResolver.linkString(in: input),
              let url = LinkResolver.normalizedURL(from: link) else {
            throw ResolveError.invalidURL
        }
        let feed = try await fetchFeed(url)
        subscribe(feed)
        return feed
    }

    // MARK: - Helpers

    private func fetchFeed(_ url: URL) async throws -> PodcastFeed {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ResolveError.network("HTTP error")
        }
        // Real feeds reach tens of megabytes (Syntax.fm ~10 MB, The Daily ~20 MB) and `XMLParser`
        // is synchronous, so parsing must not happen on this @MainActor class.
        return try await FeedParser.parseDetached(data: data, feedURL: response.url ?? url)
    }

    private func downloadLatest(_ count: Int, from feed: PodcastFeed) {
        let library = LibraryStore.shared
        let manager = DownloadManager.shared
        for episode in feed.episodes.prefix(count) {
            guard !library.records.contains(where: { $0.remoteURL == episode.enclosureURL }) else { continue }
            manager.start(episode.media(feed: feed))
        }
    }

    // MARK: - Persistence

    private func load() {
        let result = PersistedIndex.load(PodcastFeed.self,
                                         from: fileURL,
                                         label: L("subscriptions", "订阅"))
        feeds = result.items
        persistenceWarning = result.warning
        canSave = result.canSave
        if let warning = result.warning { NSLog("PodcastStore: \(warning)") }
    }

    private func save() {
        guard canSave else { return }
        PersistedIndex.save(feeds, to: fileURL)
    }
}

// MARK: - OPML

extension PodcastStore {
    /// OPML document for exporting the subscription list.
    var opmlDocument: String {
        let entries = sortedFeeds.map { feed in
            let title = Self.escapeXML(feed.title)
            let url = Self.escapeXML(feed.feedURL.absoluteString)
            return "    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(url)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>FluxKit subscriptions</title>
          </head>
          <body>
        \(entries.joined(separator: "\n"))
          </body>
        </opml>
        """
    }

    /// Reads `xmlUrl` attributes from an OPML document.
    nonisolated static func feedURLs(inOPML data: Data) -> [URL] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        let pattern = "<outline\\b[^>]*\\bxmlUrl\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [URL] = []
        var seen = Set<String>()
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            var value = String(text[valueRange])
                .replacingOccurrences(of: "&amp;", with: "&")
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value), url.scheme?.hasPrefix("http") == true else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
