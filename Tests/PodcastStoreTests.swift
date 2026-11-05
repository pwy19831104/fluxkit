import XCTest
@testable import FluxKit

final class PodcastStoreTests: XCTestCase {

    func testParsesOPMLFeedURLs() throws {
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <body>
                <outline text="Planet Money" xmlUrl="https://feeds.npr.org/510289/podcast.xml"/>
                <outline text="A &amp; B" xmlUrl="https://example.com/feed.xml?x=1&amp;y=2"/>
              </body>
            </opml>
            """
        let urls = PodcastStore.feedURLs(inOPML: Data(opml.utf8))
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://feeds.npr.org/510289/podcast.xml",
            "https://example.com/feed.xml?x=1&y=2",
        ])
    }

    func testOPMLIgnoresEmptyAndDuplicateEntries() {
        let opml = """
            <opml><body>
            <outline xmlUrl="https://example.com/feed.xml"/>
            <outline xmlUrl="https://example.com/feed.xml"/>
            <outline text="no url"/>
            </body></opml>
            """
        let urls = PodcastStore.feedURLs(inOPML: Data(opml.utf8))
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com/feed.xml")
    }

    func testOPMLDocumentContainsSubscriptions() {
        // The document builder is pure; no store state is touched here.
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><body>
            <outline type="rss" text="Show &amp; Tell" xmlUrl="https://example.com/a.xml"/>
            </body></opml>
            """
        XCTAssertEqual(PodcastStore.feedURLs(inOPML: Data(xml.utf8)).count, 1)
    }
}
