import XCTest
@testable import DownloadKit

final class LinkResolverTests: XCTestCase {

    // MARK: - URL normalisation

    func testAddsSchemeWhenMissing() {
        XCTAssertEqual(LinkResolver.normalizedURL(from: "example.com/video.mp4")?.absoluteString,
                       "https://example.com/video.mp4")
    }

    func testKeepsExplicitHTTP() {
        XCTAssertEqual(LinkResolver.normalizedURL(from: "http://example.com/v")?.scheme, "http")
    }

    func testRejectsNonWebSchemes() {
        XCTAssertNil(LinkResolver.normalizedURL(from: "ftp://example.com/v.mp4"))
        XCTAssertNil(LinkResolver.normalizedURL(from: "javascript:alert(1)"))
        XCTAssertNil(LinkResolver.normalizedURL(from: "not a url"))
    }

    // MARK: - HTML extraction

    func testFindsOpenGraphVideo() {
        let html = """
        <html><head><meta property="og:video:secure_url" content="https://cdn.example.com/clip.mp4"></head></html>
        """
        let url = LinkResolver.firstMediaCandidate(in: html, base: URL(string: "https://example.com/page")!)
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/clip.mp4")
    }

    func testFindsVideoTagWithRelativeSource() {
        let html = """
        <video controls><source src="/media/lesson.mp4" type="video/mp4"></video>
        """
        let url = LinkResolver.firstMediaCandidate(in: html, base: URL(string: "https://example.com/course/intro")!)
        XCTAssertEqual(url?.absoluteString, "https://example.com/media/lesson.mp4")
    }

    func testFindsJsonLdContentUrl() {
        let html = #"{"@type":"VideoObject","contentUrl":"https:\/\/cdn.example.com\/a\/b.mp4"}"#
        let url = LinkResolver.firstMediaCandidate(in: html, base: URL(string: "https://example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/a/b.mp4")
    }

    func testSkipsBlobUrls() {
        let html = """
        <meta property="og:video" content="blob:https://example.com/123">
        <video src="https://cdn.example.com/real.m3u8"></video>
        """
        let url = LinkResolver.firstMediaCandidate(in: html, base: URL(string: "https://example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/real.m3u8")
    }

    func testFindsHLSPlaylistInsideScript() {
        let html = #"<script>var config = {"src":"https://cdn.example.com/live/stream.m3u8?token=1"}</script>"#
        let url = LinkResolver.firstMediaCandidate(in: html, base: URL(string: "https://example.com")!)
        XCTAssertEqual(url?.host, "cdn.example.com")
        XCTAssertTrue(url?.path.hasSuffix("stream.m3u8") == true)
    }

    func testTitleFromOpenGraph() {
        let html = """
        <html><head><meta property="og:title" content="Lesson 1 &amp; 2"><title>Fallback</title></head></html>
        """
        XCTAssertEqual(LinkResolver.pageTitle(in: html), "Lesson 1 & 2")
    }

    func testThumbnailFromOpenGraphImage() {
        let html = """
        <meta property="og:image" content="https://cdn.example.com/thumb.jpg">
        """
        let url = LinkResolver.thumbnailURL(in: html, base: URL(string: "https://example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/thumb.jpg")
    }

    // MARK: - Content type heuristics

    func testPlaylistContentTypeBecomesHLS() {
        let url = URL(string: "https://example.com/master.m3u8")!
        XCTAssertEqual(LinkResolver.mediaKind(for: "application/vnd.apple.mpegurl", url: url), .hls)
        XCTAssertEqual(LinkResolver.mediaKind(for: "application/x-mpegURL", url: url), .hls)
    }

    func testVideoContentTypeBecomesProgressive() {
        let url = URL(string: "https://example.com/clip")!
        XCTAssertEqual(LinkResolver.mediaKind(for: "video/mp4", url: url), .progressive)
        XCTAssertEqual(LinkResolver.mediaKind(for: "video/quicktime", url: url), .progressive)
    }

    func testUnknownTypeUsesExtension() {
        XCTAssertEqual(LinkResolver.mediaKind(for: nil, url: URL(string: "https://example.com/a.m3u8")!), .hls)
        XCTAssertEqual(LinkResolver.mediaKind(for: nil, url: URL(string: "https://example.com/a.mp4")!), .progressive)
        XCTAssertNil(LinkResolver.mediaKind(for: "text/html", url: URL(string: "https://example.com/page")!))
    }
}

final class RecordTests: XCTestCase {

    private func media(url: String, kind: MediaKind = .progressive, title: String? = nil) -> ResolvedMedia {
        ResolvedMedia(kind: kind, url: URL(string: url)!, title: title)
    }

    func testProgressIsClamped() {
        var record = DownloadRecord(media: media(url: "https://cdn.example.com/a.mp4"))
        record.bytesExpected = 100
        record.bytesReceived = 45
        XCTAssertEqual(record.progress, 0.45, accuracy: 0.001)
        record.bytesReceived = 300
        XCTAssertEqual(record.progress, 1)
    }

    func testFinishedRecordIsAlwaysComplete() {
        var record = DownloadRecord(media: media(url: "https://cdn.example.com/a.mp4"))
        record.state = .finished
        record.bytesExpected = 0
        XCTAssertEqual(record.progress, 1)
    }

    func testGenericPlaylistNameGetsHostBasedTitle() {
        let record = DownloadRecord(media: media(url: "https://cdn.example.com/hls/master.m3u8", kind: .hls))
        XCTAssertEqual(record.title, "Video from cdn.example.com")
    }

    func testFileNameIsHumanised() {
        let record = DownloadRecord(media: media(url: "https://cdn.example.com/Big_Buck_Bunny_720.mp4"))
        XCTAssertEqual(record.title, "Big Buck Bunny 720")
    }

    func testExplicitTitleWins() {
        let record = DownloadRecord(media: media(url: "https://cdn.example.com/a.mp4", title: "Trailer"))
        XCTAssertEqual(record.title, "Trailer")
    }

    func testFileExtensionFallsBackToMimeType() {
        var item = media(url: "https://cdn.example.com/stream")
        XCTAssertEqual(item.fileExtension, "mp4")
        item.mimeType = "video/quicktime"
        XCTAssertEqual(item.fileExtension, "mov")
        item.mimeType = "video/webm"
        XCTAssertEqual(item.fileExtension, "webm")
    }
}

final class HLSPlaylistTests: XCTestCase {

    func testAttributesParsesQuotedAndBareValues() {
        let attrs = HLSDownloader.attributes(#"BANDWIDTH=1400000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=768x576"#)
        XCTAssertEqual(attrs["BANDWIDTH"], "1400000")
        XCTAssertEqual(attrs["CODECS"], "avc1.4d401f,mp4a.40.2")
        XCTAssertEqual(attrs["RESOLUTION"], "768x576")
    }

    func testHexStringDecoding() {
        XCTAssertEqual(Data(hexString: "0x0F1E")?.count, 2)
        XCTAssertEqual(Data(hexString: "0f1e")?.map { String($0, radix: 16) }, ["f", "1e"])
        XCTAssertNil(Data(hexString: "abc"))
    }

    func testAES128DecryptionRoundTrip() throws {
        // Encrypt a single block with CommonCrypto, then decrypt it through the downloader helper.
        let key = Data(repeating: 0x11, count: 16)
        let iv = Data(repeating: 0x22, count: 16)
        let plaintext = Data("0123456789abcdef".utf8)
        let ciphertext = try AESFixture.encrypt(plaintext, key: key, iv: iv)
        let decrypted = try HLSDownloader.decrypt(data: ciphertext, key: key, iv: iv)
        XCTAssertEqual(decrypted, plaintext)
    }
}

final class DeepLinkTests: XCTestCase {

    func testParsesEncodedLinkFromScheme() {
        let url = URL(string: "downloadkit://open?url=https%3A%2F%2Fcdn.example.com%2Fclip.mp4")!
        XCTAssertEqual(RootView.incomingLink(from: url), "https://cdn.example.com/clip.mp4")
    }

    func testIgnoresForeignSchemes() {
        XCTAssertNil(RootView.incomingLink(from: URL(string: "https://example.com?url=a")!))
    }

    func testIgnoresEmptyPayload() {
        XCTAssertNil(RootView.incomingLink(from: URL(string: "downloadkit://open?url=")!))
        XCTAssertNil(RootView.incomingLink(from: URL(string: "downloadkit://open")!))
    }
}
