import XCTest
@testable import FluxKit

/// The rules for automatically re-resolving a page link when its signed media address
/// lapses mid-download. The transfers themselves need a real server, so the decision logic
/// is what's covered here.
final class DownloadManagerRefreshTests: XCTestCase {

    private let pageURL = URL(string: "https://haokan.baidu.com/v?vid=15205124192539636994&tab=recommend")!
    private let signedURL = URL(string: "https://vd3.bdstatic.com/mda-x/cae_h264/1/mda-x.mp4?auth_key=1793906767-0-0-abc")!
    private let freshURL = URL(string: "https://vd3.bdstatic.com/mda-x/cae_h264/1/mda-x.mp4?auth_key=1793919999-0-0-def")!

    private func record(kind: MediaKind = .progressive,
                        remote: URL? = nil) -> DownloadRecord {
        DownloadRecord(media: ResolvedMedia(
            kind: kind,
            url: remote ?? signedURL,
            title: "拿照片威胁去308，张律怒斥，这事不简单",
            mimeType: "video/mp4",
            contentLength: 29_959_551,
            thumbnailURL: nil,
            pageURL: pageURL,
            httpHeaders: ["Referer": pageURL.absoluteString]
        ))
    }

    // MARK: - When a refresh is allowed

    func testRefreshesPageSourcedDownload() {
        XCTAssertTrue(DownloadManager.canRefreshSource(for: record(), lastRefresh: nil, isOnline: true))
    }

    func testDoesNotRefreshDirectLink() {
        // Pasting the .mp4 itself: resolving it again just returns the same dead address.
        let direct = record(remote: signedURL)
        var withSameSource = direct
        withSameSource.sourceURL = signedURL
        XCTAssertFalse(DownloadManager.canRefreshSource(for: withSameSource, lastRefresh: nil, isOnline: true))
    }

    func testDoesNotRefreshHLS() {
        XCTAssertFalse(DownloadManager.canRefreshSource(for: record(kind: .hls), lastRefresh: nil, isOnline: true))
    }

    func testDoesNotRefreshWhileOffline() {
        XCTAssertFalse(DownloadManager.canRefreshSource(for: record(), lastRefresh: nil, isOnline: false))
    }

    func testRespectsCooldown() {
        let now = Date()
        let justRefreshed = now.addingTimeInterval(-DownloadManager.sourceRefreshCooldown / 2)
        XCTAssertFalse(DownloadManager.canRefreshSource(for: record(), lastRefresh: justRefreshed, isOnline: true, now: now))
    }

    func testAllowsRefreshOnceCooldownElapsed() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-(DownloadManager.sourceRefreshCooldown + 1))
        XCTAssertTrue(DownloadManager.canRefreshSource(for: record(), lastRefresh: longAgo, isOnline: true, now: now))
    }

    // MARK: - Which failures count as "the address lapsed"

    func testBadServerResponseCountsAsRejection() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        XCTAssertTrue(DownloadManager.isRejectedAddress(error))
    }

    func testOfflineIsNotARejection() {
        // Retrying a dead address while offline would burn the cooldown for nothing.
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertFalse(DownloadManager.isRejectedAddress(error))
    }

    // MARK: - Response inspection

    func testSuccessStatusIsNotARejection() throws {
        for code in [200, 206, 204] {
            let response = try XCTUnwrap(HTTPURLResponse(url: signedURL, statusCode: code,
                                                         httpVersion: nil, headerFields: nil))
            XCTAssertNil(DownloadManager.rejectionStatus(from: response), "HTTP \(code)")
        }
    }

    func testErrorPagesAreRejections() throws {
        for code in DownloadManager.rejectedStatusCodes {
            let response = try XCTUnwrap(HTTPURLResponse(url: signedURL, statusCode: code,
                                                         httpVersion: nil, headerFields: nil))
            XCTAssertEqual(DownloadManager.rejectionStatus(from: response), code)
        }
    }

    func testMissingResponseIsNotARejection() {
        XCTAssertNil(DownloadManager.rejectionStatus(from: nil))
    }

    // MARK: - What the user is told when recovery is impossible

    func testDeletedFileIsNotBlamedOnExpiry() {
        XCTAssertEqual(DownloadManager.message(forRejectedStatus: 404),
                       L("The server no longer has that file.", "服务器上已经没有这个文件了。"))
        XCTAssertEqual(DownloadManager.message(forRejectedStatus: 410),
                       L("The server no longer has that file.", "服务器上已经没有这个文件了。"))
    }

    func testForbiddenIsReportedAsExpiredLink() {
        let expired = L("The site's playback link had expired and a new one couldn't be fetched. Paste the page link again to refresh it.",
                        "网站的播放地址已过期，暂时没能换到新的。重新粘贴一遍页面链接就能刷新。")
        XCTAssertEqual(DownloadManager.message(forRejectedStatus: 403), expired)
        XCTAssertEqual(DownloadManager.message(forRejectedStatus: 401), expired)
    }

    // MARK: - Stale task callbacks

    func testReplacedTaskIsNoLongerCurrent() {
        let registry = TaskRegistry()
        let recordID = UUID()
        let entry = TaskRegistry.Entry(recordID: recordID, fileExtension: "mp4")

        registry.register(entry, for: 7)
        XCTAssertTrue(registry.isCurrent(taskID: 7, recordID: recordID))

        // The lapsed address was re-resolved and a new task took over the record.
        registry.register(entry, for: 8)
        XCTAssertFalse(registry.isCurrent(taskID: 7, recordID: recordID))
        XCTAssertTrue(registry.isCurrent(taskID: 8, recordID: recordID))
    }

    func testUnknownTaskIsTreatedAsCurrent() {
        // Tasks re-delivered after a relaunch may not be registered yet; never swallow those.
        let registry = TaskRegistry()
        XCTAssertTrue(registry.isCurrent(taskID: 42, recordID: UUID()))
    }
    // MARK: - Unusable resume data

    func testResumeRejectionRestartsFromZero() {
        // The server no longer has the range we resumed from.
        for code in [NSURLErrorBadServerResponse,
                     NSURLErrorCannotParseResponse,
                     NSURLErrorResourceUnavailable,
                     NSURLErrorCannotDecodeContentData,
                     NSURLErrorUnsupportedURL] {
            XCTAssertTrue(
                DownloadManager.shouldRestartWithoutResume(
                    usedResumeData: true,
                    error: NSError(domain: NSURLErrorDomain, code: code)
                ),
                "\(code) should restart the download"
            )
        }
    }

    func testTransportFailuresDoNotRestart() {
        // Throwing away a 900 MB partial download because the phone lost signal would be cruel.
        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost] {
            XCTAssertFalse(
                DownloadManager.shouldRestartWithoutResume(
                    usedResumeData: true,
                    error: NSError(domain: NSURLErrorDomain, code: code)
                ),
                "\(code) must keep the resume data"
            )
        }
    }

    func testRestartOnlyAppliesToResumedTransfers() {
        XCTAssertFalse(DownloadManager.shouldRestartWithoutResume(
            usedResumeData: false,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        ))
        XCTAssertFalse(DownloadManager.shouldRestartWithoutResume(
            usedResumeData: true,
            error: NSError(domain: "SomeOtherDomain", code: 1)
        ))
    }

}
