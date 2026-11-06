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
    // MARK: - tv.sohu.com

    func testSohuVideoIDComesFromThePage() {
        let html = #"<script>var vid="10760370";var tvid = "754854689";</script>"#
        XCTAssertEqual(SiteExtractor.Sohu.videoID(inHTML: html), "10760370")
        XCTAssertNil(SiteExtractor.Sohu.videoID(inHTML: "<html>no id here</html>"))
    }

    func testSohuEndpointAsksForTheVideonewPayload() throws {
        let page = try XCTUnwrap(URL(string: "https://tv.sohu.com/v/MjAyNjExMDQvbjYyMDI2OTUxNi5zaHRtbA==.html"))
        let endpoint = SiteExtractor.Sohu.endpoint(videoID: "10760370", pageURL: page)
        let components = try XCTUnwrap(URLComponents(url: endpoint, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "my.tv.sohu.com")
        XCTAssertEqual(components.path, "/play/videonew.do")
        XCTAssertEqual(components.queryItems?.first { $0.name == "vid" }?.value, "10760370")
    }

    private func sohuPayload(play: Int = 1,
                            payData: [String: Any] = [:],
                            mp4: [String] = [],
                            clips: [String] = []) -> [String: Any] {
        [
            "status": 1,
            "play": play,
            "pay_data": payData,
            "data": [
                "tvName": "土耳其旅游之-蓝色之旅",
                "mp4PlayUrl": mp4,
                "clipsURL": clips,
                "coverImg": "http://e3f49eaa46b57.cdn.sohucs.com/group1/M01/88/8D/cover.jpg",
                "totalBytes": 16_555_146
            ]
        ]
    }

    func testSohuPicksTheProgressiveFile() throws {
        let token = "http://data.vod.itc.cn/?k=abc&a=def"
        let extraction = try SiteExtractor.Sohu.extraction(fromJSONObject: sohuPayload(mp4: [token]))
        XCTAssertEqual(extraction.url.absoluteString, token)
        XCTAssertEqual(extraction.title, "土耳其旅游之-蓝色之旅")
        XCTAssertEqual(extraction.contentLength, 16_555_146)
        XCTAssertEqual(extraction.thumbnailURL?.host, "e3f49eaa46b57.cdn.sohucs.com")
    }

    func testSohuFallsBackToThePlaylistList() throws {
        let extraction = try SiteExtractor.Sohu.extraction(
            fromJSONObject: sohuPayload(clips: ["http://data.vod.itc.cn/?k=abc&a=def"])
        )
        XCTAssertEqual(extraction.mimeType, "application/vnd.apple.mpegurl")
    }

    func testSohuVIPEpisodeExplainsItself() {
        for payload in [sohuPayload(play: 0), sohuPayload(payData: ["isPay": 1])] {
            XCTAssertThrowsError(try SiteExtractor.Sohu.extraction(fromJSONObject: payload)) { error in
                guard let resolveError = error as? ResolveError,
                      case .protectedStream = resolveError else {
                    return XCTFail("expected protectedStream, got \(error)")
                }
            }
        }
    }

    func testSohuPayloadWithoutAnyAddressThrows() {
        XCTAssertThrowsError(try SiteExtractor.Sohu.extraction(fromJSONObject: sohuPayload())) { error in
            XCTAssertEqual(error as? ResolveError, .noMediaFound)
        }
    }

    // MARK: - Charset fallback

    func testGBKPageIsDecodedInsteadOfBecomingEmpty() {
        // 搜狐视频 serves GBK; decoding it as UTF-8 fails, and an empty string used to look
        // like "no video on this page".
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let html = #"<script>var vid="10760370";</script>"#
        let data = html.data(using: gbk)!
        let decoded = LinkResolver.decodedText(from: data)
        XCTAssertEqual(SiteExtractor.Sohu.videoID(inHTML: decoded), "10760370")
    }

    func testUTF8PageStillDecodes() {
        let html = #"<script>var vid="10760370";</script>"#
        XCTAssertEqual(SiteExtractor.Sohu.videoID(inHTML: LinkResolver.decodedText(from: html.data(using: .utf8)!)),
                       "10760370")
    }

    // MARK: - mbd.baidu.com

    /// Trimmed copy of the `window.jsonData` payload a videolanding page ships inline.
    private func baiduHTML(title: String = "邓超和Angelababy合体比心") -> String {
        #"""
        <!DOCTYPE html><html><head><title>x</title></head><body>
        <script>
        window.jsonData = {"author":{"name":"三湘都市报","vip":2},"playCount":"203638",
        "curVideoMeta":{"id":"4501778114630897145","title":"\#(title)","duration":16,
        "playurl":"https:\/\/vd4.bdstatic.com\/mda-x\/720p_frame30\/1\/mda-x.mp4",
        "clarityUrl":[
          {"title":"标清","url":"https:\/\/vd4.bdstatic.com\/mda-x\/540p\/2\/mda-x.mp4","videoSize":1.8},
          {"title":"超清","url":"https:\/\/vd4.bdstatic.com\/mda-x\/720p_frame30\/1\/mda-x.mp4","videoSize":2.1}
        ]},"isNextVideo":1};
        window.whiteScreenTime = performance.now();
        </script></body></html>
        """#
    }

    func testBaiduReadsInlineVideoMeta() throws {
        let extraction = try SiteExtractor.Baidu.extraction(fromHTML: baiduHTML())
        XCTAssertEqual(extraction.url.absoluteString,
                       "https://vd4.bdstatic.com/mda-x/720p_frame30/1/mda-x.mp4")
        XCTAssertEqual(extraction.title, "邓超和Angelababy合体比心")
    }

    func testBaiduPrefersTheLargestRendition() throws {
        // 超清 (2.1 MB) beats 标清 (1.8 MB) even though it is listed second.
        let extraction = try SiteExtractor.Baidu.extraction(fromHTML: baiduHTML())
        XCTAssertTrue(extraction.url.absoluteString.contains("720p_frame30"))
    }

    func testBaiduFallsBackToPlayURLWhenRenditionsAreMissing() throws {
        let html = ##"<script>window.jsonData = {"curVideoMeta":{"title":"t","clarityUrl":[],"playurl":"https:\/\/vd4.bdstatic.com\/a.mp4"}};</script>"##
        let extraction = try SiteExtractor.Baidu.extraction(fromHTML: html)
        XCTAssertEqual(extraction.url.absoluteString, "https://vd4.bdstatic.com/a.mp4")
    }

    func testBaiduPageWithoutJsonDataThrows() {
        XCTAssertThrowsError(try SiteExtractor.Baidu.extraction(fromHTML: "<html><body>no data</body></html>")) { error in
            XCTAssertEqual(error as? ResolveError, .noMediaFound)
        }
    }

    func testBaiduNullVideoMetaDoesNotSwallowTheNextObject() {
        // `"curVideoMeta":null` must not be matched against some later object.
        let html = ##"<script>window.jsonData = {"curVideoMeta":null,"next":{"url":"https:\/\/x\/a.mp4"}};</script>"##
        XCTAssertThrowsError(try SiteExtractor.Baidu.extraction(fromHTML: html))
    }

    func testJSONSliceHandlesBracesInsideStrings() {
        let html = ##"window.jsonData = {"curVideoMeta":{"title":"a } b { c","playurl":"https:\/\/v\/a.mp4"},"tail":1};"##
        let slice = SiteExtractor.jsonObjectSlice(after: "\"curVideoMeta\"", in: html)
        XCTAssertEqual(slice, ##"{"title":"a } b { c","playurl":"https:\/\/v\/a.mp4"}"##)
    }

    /// The second `window.jsonData` shape Baidu serves (`data.videoInfo` / `clarityArr`).
    func testBaiduHandlesTheVideoInfoShape() throws {
        let html = ##"""
        <script>window.jsonData= {"errno":"0","data":{"id":"4501778114630897145","title":"邓超和Angelababy",
        "videoInfo":{"posterImage":"http://vd3.bdstatic.com/mda-x/1/mda-x00000000.jpg@f_auto",
        "title":"邓超和Angelababy","vid":"4501778114630897145","duration":16,
        "play_url":"http://vd4.bdstatic.com/mda-x/540p/2/mda-x.mp4?v_from_s=bdapp",
        "clarityArr":[{"key":"sc","title":"超清","url":"http://vd4.bdstatic.com/mda-x/720p/1/mda-x.mp4","videoSize":2.1},
                      {"key":"sd","title":"标清","url":"http://vd4.bdstatic.com/mda-x/540p/2/mda-x.mp4","videoSize":1.8}]}},
        "timestamp":1};</script>
        """##
        let extraction = try SiteExtractor.Baidu.extraction(fromHTML: html)
        XCTAssertEqual(extraction.url.absoluteString, "https://vd4.bdstatic.com/mda-x/720p/1/mda-x.mp4")
        XCTAssertEqual(extraction.url.scheme, "https")
        XCTAssertEqual(extraction.title, "邓超和Angelababy")
        XCTAssertEqual(extraction.thumbnailURL?.scheme, "https")
    }

    func testBaiduUpgradesHTTPCDNAddressesToHTTPS() throws {
        let extraction = try SiteExtractor.Baidu.extraction(fromHTML: baiduHTML())
        XCTAssertEqual(extraction.url.scheme, "https")
    }

    // MARK: - reddit.com

    func testRedditPostIDFromPostAndShortLinks() throws {
        let post = try XCTUnwrap(URL(string: "https://www.reddit.com/r/BoyDinnerDiaries/comments/1xoatqp/fiance_wants_a_month_break/"))
        XCTAssertEqual(SiteExtractor.Reddit.postID(in: post), "1xoatqp")
        let short = try XCTUnwrap(URL(string: "https://redd.it/1xoatqp"))
        XCTAssertEqual(SiteExtractor.Reddit.postID(in: short), "1xoatqp")
        let notPost = try XCTUnwrap(URL(string: "https://www.reddit.com/r/BoyDinnerDiaries/"))
        XCTAssertNil(SiteExtractor.Reddit.postID(in: notPost))
    }

    func testRedditEndpointPointsAtTheJSONView() throws {
        let post = try XCTUnwrap(URL(string: "https://www.reddit.com/r/x/comments/1xoatqp/slug/"))
        let endpoint = SiteExtractor.Reddit.endpoint(for: post, postID: "1xoatqp")
        XCTAssertEqual(endpoint.absoluteString, "https://www.reddit.com/comments/1xoatqp.json?raw_json=1")
    }

    /// Trimmed copy of the `/comments/<id>.json` payload (post listing + comments listing).
    private func redditPayload(hls: String? = "https://v.redd.it/abc123/HLSPlaylist.m3u8?x=1",
                               fallback: String? = "https://v.redd.it/abc123/DASH_720.mp4?source=fallback") -> Any {
        var video: [String: Any] = ["duration": 42, "width": 1280, "height": 720]
        if let hls { video["hls_url"] = hls }
        if let fallback { video["fallback_url"] = fallback }
        return [
            ["kind": "Listing", "data": ["children": [["kind": "t3", "data": [
                "title": "Fiancé wants a month break",
                "secure_media": ["reddit_video": video]
            ] as [String: Any]]]]],
            ["kind": "Listing", "data": ["children": []]]
        ]
    }

    func testRedditPrefersHLSBecauseAudioIsASeparateRendition() throws {
        let extraction = try SiteExtractor.Reddit.extraction(fromJSONValue: redditPayload())
        XCTAssertEqual(extraction.url.absoluteString, "https://v.redd.it/abc123/HLSPlaylist.m3u8?x=1")
        XCTAssertEqual(extraction.mimeType, "application/vnd.apple.mpegurl")
        XCTAssertEqual(extraction.title, "Fiancé wants a month break")
    }

    func testRedditFallsBackToTheVideoTrackWhenThereIsNoHLS() throws {
        let extraction = try SiteExtractor.Reddit.extraction(fromJSONValue: redditPayload(hls: nil))
        XCTAssertEqual(extraction.url.absoluteString, "https://v.redd.it/abc123/DASH_720.mp4?source=fallback")
        XCTAssertNil(extraction.mimeType)
    }

    func testRedditReadsOlderPostsUnderMedia() throws {
        let payload: [[String: Any]] = [["kind": "Listing", "data": ["children": [["kind": "t3", "data": [
            "title": "older",
            "media": ["reddit_video": ["hls_url": "https://v.redd.it/zzz/HLSPlaylist.m3u8"]]
        ] as [String: Any]]]]]]
        let extraction = try SiteExtractor.Reddit.extraction(fromJSONValue: payload)
        XCTAssertEqual(extraction.url.absoluteString, "https://v.redd.it/zzz/HLSPlaylist.m3u8")
    }

    func testRedditTextPostThrows() {
        let payload: [[String: Any]] = [["kind": "Listing", "data": ["children": [["kind": "t3", "data": [
            "title": "just text"
        ] as [String: Any]]]]]]
        XCTAssertThrowsError(try SiteExtractor.Reddit.extraction(fromJSONValue: payload)) { error in
            XCTAssertEqual(error as? ResolveError, .noMediaFound)
        }
    }

}
