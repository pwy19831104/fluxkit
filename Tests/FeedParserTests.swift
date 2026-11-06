import XCTest
@testable import FluxKit

final class FeedParserTests: XCTestCase {

    private let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>The Example Show</title>
            <itunes:author>Example Media</itunes:author>
            <itunes:image href="https://cdn.example.com/cover.jpg"/>
            <item>
              <title>Older episode &amp; friends</title>
              <pubDate>Mon, 02 Sep 2024 10:00:00 +0000</pubDate>
              <itunes:duration>24:30</itunes:duration>
              <enclosure url="https://cdn.example.com/old.mp3" length="24000000" type="audio/mpeg"/>
            </item>
            <item>
              <title>Newest episode</title>
              <pubDate>Mon, 09 Sep 2024 10:00:00 +0000</pubDate>
              <itunes:duration>1:02:03</itunes:duration>
              <itunes:image href="https://cdn.example.com/episode.jpg"/>
              <enclosure url="https://cdn.example.com/new.m4a" length="58000000" type="audio/x-m4a"/>
            </item>
          </channel>
        </rss>
        """

    func testParsesRSSEpisodesNewestFirst() throws {
        let feed = try FeedParser.parse(text: rss, feedURL: URL(string: "https://example.com/feed.xml")!)

        XCTAssertEqual(feed.title, "The Example Show")
        XCTAssertEqual(feed.author, "Example Media")
        XCTAssertEqual(feed.artworkURL?.absoluteString, "https://cdn.example.com/cover.jpg")
        XCTAssertEqual(feed.episodes.count, 2)

        let newest = try XCTUnwrap(feed.episodes.first)
        XCTAssertEqual(newest.title, "Newest episode")
        XCTAssertEqual(newest.enclosureURL.absoluteString, "https://cdn.example.com/new.m4a")
        XCTAssertEqual(newest.mimeType, "audio/x-m4a")
        XCTAssertEqual(newest.byteLength, 58_000_000)
        XCTAssertEqual(newest.duration ?? 0, 3723, accuracy: 0.5)
        XCTAssertEqual(newest.artworkURL?.absoluteString, "https://cdn.example.com/episode.jpg")

        let older = feed.episodes[1]
        XCTAssertEqual(older.title, "Older episode & friends", "HTML entities should be decoded")
        XCTAssertEqual(older.duration ?? 0, 1470, accuracy: 0.5)
    }

    func testParsesAtomEnclosureLinks() throws {
        let atom = """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <title>Atom Cast</title>
              <entry>
                <title>Episode One</title>
                <published>2024-09-09T10:00:00Z</published>
                <link rel="enclosure" href="https://cdn.example.com/one.mp3" type="audio/mpeg" length="1234"/>
              </entry>
            </feed>
            """
        let feed = try FeedParser.parse(text: atom, feedURL: URL(string: "https://example.com/atom.xml")!)
        XCTAssertEqual(feed.title, "Atom Cast")
        XCTAssertEqual(feed.episodes.count, 1)
        XCTAssertEqual(feed.episodes[0].enclosureURL.absoluteString, "https://cdn.example.com/one.mp3")
        XCTAssertEqual(feed.episodes[0].byteLength, 1234)
    }

    func testRejectsPagesThatAreNotFeeds() {
        XCTAssertFalse(FeedParser.looksLikeFeedText("<html><body>hello</body></html>"))
        XCTAssertThrowsError(
            try FeedParser.parse(text: "<html><body>hello</body></html>",
                                 feedURL: URL(string: "https://example.com")!)
        )
    }

    func testFeedWithoutEnclosuresThrows() {
        let empty = """
            <rss><channel><title>Empty</title>
            <item><title>No media</title></item>
            </channel></rss>
            """
        XCTAssertThrowsError(
            try FeedParser.parse(text: empty, feedURL: URL(string: "https://example.com/feed")!)
        )
    }

    func testDetectsFeedContentTypesAndExtensions() {
        XCTAssertTrue(FeedParser.looksLikeFeed(contentType: "application/rss+xml", url: URL(string: "https://a.com/x")!))
        XCTAssertTrue(FeedParser.looksLikeFeed(contentType: nil, url: URL(string: "https://a.com/feed.xml")!))
        XCTAssertFalse(FeedParser.looksLikeFeed(contentType: "video/mp4", url: URL(string: "https://a.com/x.mp4")!))
    }

    func testFeedRoundTripsThroughCodable() throws {
        let feed = try FeedParser.parse(text: rss, feedURL: URL(string: "https://example.com/feed.xml")!)
        let data = try JSONEncoder().encode(feed)
        let decoded = try JSONDecoder().decode(PodcastFeed.self, from: data)
        XCTAssertEqual(decoded.feedURL, feed.feedURL)
        XCTAssertEqual(decoded.title, feed.title)
        XCTAssertEqual(decoded.episodes.count, feed.episodes.count)
        XCTAssertEqual(decoded.episodes.first?.enclosureURL, feed.episodes.first?.enclosureURL)
    }

    func testEpisodeMapsToDownloadableMedia() throws {
        let feed = try FeedParser.parse(text: rss, feedURL: URL(string: "https://example.com/feed.xml")!)
        let episode = try XCTUnwrap(feed.episodes.first)
        let media = episode.media(feed: feed)
        XCTAssertEqual(media.kind, .progressive)
        XCTAssertEqual(media.url, episode.enclosureURL)
        XCTAssertEqual(media.title, episode.title)
        XCTAssertEqual(media.thumbnailURL?.absoluteString, "https://cdn.example.com/episode.jpg")
        XCTAssertEqual(media.pageURL?.absoluteString, "https://example.com/feed.xml")
    }
    /// Feeds can be huge — Syntax.fm ships ~10 MB, The Daily ~20 MB. Truncating the document at a
    /// byte budget cuts the XML mid-tree, and `XMLParser` then reports a malformed document, which
    /// the app showed as "that doesn't look like a podcast feed".
    func testParsesAFeedBiggerThanAnyDecodingBudget() throws {
        let filler = String(repeating: "description text ", count: 100) // ~1.7 KB per episode
        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Big Show</title>

            """
        let episodes = 3000
        for index in 0..<episodes {
            xml += """
                <item>
                  <title>Episode \(index)</title>
                  <pubDate>Mon, 09 Sep 2024 10:00:00 +0000</pubDate>
                  <description>\(filler)</description>
                  <enclosure url="https://cdn.example.com/\(index).mp3" length="1000" type="audio/mpeg"/>
                </item>

                """
        }
        xml += "</channel></rss>"
        XCTAssertGreaterThan(xml.utf8.count, 4_000_000, "the fixture must exceed the old 4 MB budget")

        // Decoding must keep the whole document.
        let text = LinkResolver.decodedText(from: Data(xml.utf8))
        XCTAssertEqual(text.utf8.count, xml.utf8.count)

        let feed = try FeedParser.parse(text: text, feedURL: URL(string: "https://example.com/big.xml")!)
        XCTAssertEqual(feed.episodes.count, episodes)
        XCTAssertEqual(feed.episodes.first?.title, "Episode 0")   // no dates → insertion order kept
    }

    /// The parse runs off the caller's actor, so a 20 MB feed cannot block the main thread.
    func testDetachedParseMatchesTheSyncPath() async throws {
        let feed = try await FeedParser.parseDetached(data: Data(rss.utf8),
                                                     feedURL: URL(string: "https://example.com/feed.xml")!)
        XCTAssertEqual(feed.title, "The Example Show")
        XCTAssertEqual(feed.episodes.count, 2)
    }

}
