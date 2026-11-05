import XCTest
@testable import FluxKit

final class SiteExtractorTests: XCTestCase {

    // MARK: - Host matching

    func testMatchesExactHostAndSubdomains() {
        XCTAssertTrue(SiteExtractor.matches("haokan.baidu.com", SiteExtractor.Haokan.hosts))
        XCTAssertTrue(SiteExtractor.matches("m.haokan.baidu.com", SiteExtractor.Haokan.hosts))
        XCTAssertFalse(SiteExtractor.matches("evilhaokan.baidu.com", SiteExtractor.Haokan.hosts))
        XCTAssertFalse(SiteExtractor.matches("baidu.com", SiteExtractor.Haokan.hosts))
    }

    func testUnknownHostIsNotClaimed() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/clip.mp4"))
        let extraction = try await SiteExtractor.extract(from: url, session: .shared)
        XCTAssertNil(extraction)
    }

    // MARK: - haokan: link shapes

    func testFindsVideoIDInQuery() throws {
        let url = try XCTUnwrap(URL(string: "https://haokan.baidu.com/v?vid=15205124192539636994&tab=recommend"))
        XCTAssertEqual(SiteExtractor.Haokan.videoID(in: url), "15205124192539636994")
    }

    func testFindsVideoIDInPath() throws {
        let url = try XCTUnwrap(URL(string: "https://haokan.baidu.com/video/15205124192539636994"))
        XCTAssertEqual(SiteExtractor.Haokan.videoID(in: url), "15205124192539636994")
    }

    func testIgnoresNonVideoPathSegments() throws {
        let url = try XCTUnwrap(URL(string: "https://haokan.baidu.com/tab/projection_hall"))
        XCTAssertNil(SiteExtractor.Haokan.videoID(in: url))
    }

    func testJSONEndpointKeepsHostAndAsksForJSON() throws {
        let page = try XCTUnwrap(URL(string: "https://haokan.baidu.com/v?vid=15205124192539636994&tab=recommend"))
        let endpoint = SiteExtractor.Haokan.endpoint(for: page, videoID: "15205124192539636994")
        let components = try XCTUnwrap(URLComponents(url: endpoint, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "haokan.baidu.com")
        XCTAssertEqual(components.path, "/v")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "vid" }?.value, "15205124192539636994")
        XCTAssertEqual(items.first { $0.name == "_format" }?.value, "json")
    }

    // MARK: - haokan: payload

    /// Trimmed copy of a real `GET /v?vid=…&_format=json` response.
    private func payload(renditions: [[String: Any]],
                         playURL: String? = nil,
                         errno: Int = 0) -> [String: Any] {
        var meta: [String: Any] = [
            "id": "15205124192539636994",
            "title": "拿照片威胁去308，张律怒斥，这事不简单",
            "poster": "http://f7.baidu.com/it/u=383325615,1064843268&fm=222&app=106&f=JPEG",
            "duration": 931,
            "clarityUrl": renditions
        ]
        if let playURL { meta["playurl"] = playURL }
        return [
            "errno": errno,
            "error": "成功",
            "data": [
                "errno": errno,
                "apiData": [
                    "curVideoMeta": meta
                ]
            ]
        ]
    }

    private let standard = "https://vdept3.bdstatic.com/mda-sjtectuk58aqfe9y/cae_h264/1793183258842251800/mda-sjtectuk58aqfe9y.mp4?auth_key=1793906644-0-0-1442c0160b8c6bd452bf532f259ae489&vid=15205124192539636994"
    private let multiBitrate = "https://vdept3.bdstatic.com/mda-sjtectuk58aqfe9y/cae_h264/1793183258842251800/mda-sjtectuk58aqfe9y_720p.mp4?auth_key=1793906644-0-0-1442c0160b8c6bd452bf532f259ae489"

    func testReadsVideoSourceFromClarityURL() throws {
        let root = payload(renditions: [["title": "标清 360P", "url": standard, "videoSize": 28.6]])
        let extraction = try SiteExtractor.Haokan.extraction(fromJSONObject: root)
        XCTAssertEqual(extraction.url.absoluteString, standard)
        XCTAssertEqual(extraction.title, "拿照片威胁去308，张律怒斥，这事不简单")
        XCTAssertEqual(extraction.thumbnailURL?.scheme, "https")
    }

    func testPicksHighestBitrateRendition() throws {
        let root = payload(renditions: [
            ["title": "标清 360P", "url": standard, "videoSize": 28.6],
            ["title": "高清 720P", "url": multiBitrate, "videoSize": 71.2]
        ])
        let extraction = try SiteExtractor.Haokan.extraction(fromJSONObject: root)
        XCTAssertEqual(extraction.url.absoluteString, multiBitrate)
    }

    func testFallsBackToPlayURLWhenNoRenditions() throws {
        let root = payload(renditions: [], playURL: standard)
        let extraction = try SiteExtractor.Haokan.extraction(fromJSONObject: root)
        XCTAssertEqual(extraction.url.absoluteString, standard)
    }

    func testSkipsBlobRendition() throws {
        let root = payload(renditions: [
            ["title": "blob", "url": "blob:https://haokan.baidu.com/1234", "videoSize": 999],
            ["title": "标清 360P", "url": standard, "videoSize": 28.6]
        ])
        let extraction = try SiteExtractor.Haokan.extraction(fromJSONObject: root)
        XCTAssertEqual(extraction.url.absoluteString, standard)
    }

    func testMissingVideoThrows() {
        let root = payload(renditions: [["url": standard, "videoSize": 28.6]], errno: 30020)
        XCTAssertThrowsError(try SiteExtractor.Haokan.extraction(fromJSONObject: root)) { error in
            XCTAssertEqual(error as? ResolveError, .noMediaFound)
        }
    }

    func testPayloadWithoutAnyAddressThrows() {
        let root = payload(renditions: [])
        XCTAssertThrowsError(try SiteExtractor.Haokan.extraction(fromJSONObject: root)) { error in
            XCTAssertEqual(error as? ResolveError, .noMediaFound)
        }
    }

    // MARK: - JSON fetching guards

    func testHTTPURLRejectsNonWebSchemes() {
        XCTAssertNil(SiteExtractor.httpURL("blob:https://example.com/1"))
        XCTAssertNil(SiteExtractor.httpURL("data:video/mp4;base64,AAAA"))
        XCTAssertNil(SiteExtractor.httpURL(""))
        XCTAssertEqual(SiteExtractor.httpURL("https:\\/\\/cdn.example.com\\/a.mp4")?.host, "cdn.example.com")
    }
}
