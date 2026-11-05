import Foundation
import Observation

/// Subscribed podcast feeds, cached episode metadata, and refresh logic.
@MainActor
@Observable
final class PodcastStore {

    static let shared = PodcastStore()

    private(set) var feeds: [PodcastFeed] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?

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

    func isSubscribed(_ feedURL: URL) -> Bool {
        feeds.contains { $0.feedURL == feedURL }
    }

    func feed(withURL url: URL) -> PodcastFeed? {
        feeds.first { $0.feedURL == url }
    }

    // MARK: - Mutations

    func subscribe(_ feed: PodcastFeed, autoDownload: Int? = nil) {
        var snapshot = feed
        snapshot.episodes = Array(feed.episodes.prefix(100))
        if let index = feeds.firstIndex(where: { $0.feedURL == feed.feedURL }) {
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
        feeds.removeAll { $0.feedURL == feedURL }
        save()
    }

    func apply(_ feed: PodcastFeed) {
        guard let index = feeds.firstIndex(where: { $0.feedURL == feed.feedURL }) else { return }
        var snapshot = feed
        snapshot.episodes = Array(feed.episodes.prefix(100))
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
        return try FeedParser.parse(data: data, feedURL: response.url ?? url)
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
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        feeds = (try? decoder.decode([PodcastFeed].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(feeds) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
