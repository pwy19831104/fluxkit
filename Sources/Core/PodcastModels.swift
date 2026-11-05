import Foundation

/// A podcast (or any RSS/Atom) feed the user pasted, reduced to what FluxKit needs.
struct PodcastFeed: Identifiable, Codable, Hashable, Sendable {
    var id: URL { feedURL }
    var title: String
    var author: String?
    var artworkURL: URL?
    var feedURL: URL
    var episodes: [PodcastEpisode]

    var host: String { feedURL.host ?? feedURL.absoluteString }
}

struct PodcastEpisode: Identifiable, Codable, Hashable, Sendable {
    var id: String { enclosureURL.absoluteString }
    var title: String
    var publishedAt: Date?
    var duration: Double?
    var byteLength: Int64?
    var enclosureURL: URL
    var mimeType: String?
    var artworkURL: URL?

    /// Media descriptor understood by the existing download pipeline.
    func media(feed: PodcastFeed) -> ResolvedMedia {
        ResolvedMedia(
            kind: .progressive,
            url: enclosureURL,
            title: title,
            mimeType: mimeType,
            contentLength: byteLength,
            thumbnailURL: artworkURL ?? feed.artworkURL,
            pageURL: feed.feedURL,
            httpHeaders: ["Referer": feed.feedURL.absoluteString]
        )
    }
}
