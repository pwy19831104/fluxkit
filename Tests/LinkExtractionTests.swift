import XCTest
@testable import FluxKit

final class LinkExtractionTests: XCTestCase {

    // MARK: - Share blurbs

    func testExtractsDouyinShareBlurb() {
        let blurb = """
        5.33 复制打开抖音，看看【水泥美的作品】语音效率比键盘高太多太多了# ai# ai工具 #... https://v.douyin.com/AfPLqZg3RJo/ w@S.LJ :6pm icN:/ 09/29
        """
        XCTAssertEqual(LinkTextExtractor.firstLink(in: blurb),
                       "https://v.douyin.com/AfPLqZg3RJo/")
    }

    func testExtractsLinkBeforeAndAfterChineseText() {
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "看这个https://cdn.example.com/a.mp4很棒"),
                       "https://cdn.example.com/a.mp4")
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "下载地址：https://cdn.example.com/a.mp4。"),
                       "https://cdn.example.com/a.mp4")
    }

    func testExtractsBareDomainFromText() {
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "复制 v.douyin.com/AfPLqZg3RJo 打开"),
                       "https://v.douyin.com/AfPLqZg3RJo")
    }

    func testStripsWrappingAnglesAndQuotes() {
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "<https://example.com/a.mp4>"),
                       "https://example.com/a.mp4")
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "见 \"https://example.com/a.mp4\""),
                       "https://example.com/a.mp4")
    }

    func testTakesTheFirstOfSeveralLinks() {
        let text = "第一个 https://a.example.com/1.mp4 第二个 https://b.example.com/2.mp4"
        XCTAssertEqual(LinkTextExtractor.firstLink(in: text), "https://a.example.com/1.mp4")
    }

    // MARK: - Rejections

    func testRejectsTextWithoutLink() {
        XCTAssertNil(LinkTextExtractor.firstLink(in: "这段文字里没有任何链接"))
        XCTAssertNil(LinkTextExtractor.firstLink(in: "   "))
    }

    func testDoesNotMistakeEmailsOrTimestampsForLinks() {
        XCTAssertNil(LinkTextExtractor.firstLink(in: "写信到 hi@example.com"))
        XCTAssertNil(LinkTextExtractor.firstLink(in: "09/29 6pm"))
        XCTAssertNil(LinkTextExtractor.firstLink(in: "1.2.3 版本"))
    }

    func testDoesNotExtractFromNonWebScheme() {
        XCTAssertNil(LinkTextExtractor.firstLink(in: "ftp://example.com/a.mp4"))
        XCTAssertNil(LinkTextExtractor.firstLink(in: "file:///Users/me/a.mp4"))
        XCTAssertNil(LinkTextExtractor.firstLink(in: "mailto:hi@example.com"))
    }

    // MARK: - Whole-string links keep working

    func testWholeStringLinks() {
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "https://example.com/a.mp4"),
                       "https://example.com/a.mp4")
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "example.com/a.mp4"),
                       "https://example.com/a.mp4")
        XCTAssertEqual(LinkTextExtractor.firstLink(in: "http://example.com:8080/a.mp4"),
                       "http://example.com:8080/a.mp4")
    }

    // MARK: - Unsupported platforms

    func testFlagsSignedPlatforms() {
        for (host, name) in [("v.douyin.com", "Douyin"),
                             ("www.tiktok.com", "TikTok"),
                             ("youtu.be", "YouTube"),
                             ("www.youtube.com", "YouTube"),
                             ("www.instagram.com", "Instagram"),
                             ("www.bilibili.com", "Bilibili")] {
            let url = URL(string: "https://\(host)/x")!
            XCTAssertEqual(LinkResolver.unsupportedPlatform(for: url), name, host)
        }
    }

    func testAllowsDirectMediaHostsAndPlatformCDNs() {
        // Direct media and platform CDNs (signed *file* URLs are fine, we never touch pages).
        for host in ["cdn.example.com", "v3-web.douyinvod.com", "video.twimg.com"] {
            let url = URL(string: "https://\(host)/clip.mp4")!
            XCTAssertNil(LinkResolver.unsupportedPlatform(for: url), host)
        }
    }
}
