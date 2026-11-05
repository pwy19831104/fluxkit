import XCTest
@testable import FluxKit

final class LocalizationTests: XCTestCase {

    // MARK: - Region → language

    func testMainlandChinaGetsChinese() {
        XCTAssertEqual(AppLanguage.resolve(regionIdentifier: "CN"), .chinese)
        XCTAssertEqual(AppLanguage.resolve(regionIdentifier: "cn"), .chinese)
    }

    func testEveryOtherRegionGetsEnglish() {
        for region in ["US", "GB", "JP", "SG", "HK", "TW", "MO", "DE", ""] {
            XCTAssertEqual(AppLanguage.resolve(regionIdentifier: region), .english, region)
        }
        XCTAssertEqual(AppLanguage.resolve(regionIdentifier: nil), .english)
    }

    // MARK: - Manual override

    func testManualChoiceBeatsTheRegion() {
        XCTAssertEqual(AppLanguage.effective(regionIdentifier: "CN", override: .english), .english)
        XCTAssertEqual(AppLanguage.effective(regionIdentifier: "US", override: .chinese), .chinese)
        XCTAssertEqual(AppLanguage.effective(regionIdentifier: "CN", override: nil), .chinese)
        XCTAssertEqual(AppLanguage.effective(regionIdentifier: "US", override: nil), .english)
    }

    func testOverrideRoundTripsThroughDefaults() {
        let suiteName = "com.fluxkit.tests.language"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(LanguagePreferences.override(in: suite))

        LanguagePreferences.setOverride(.chinese, in: suite)
        XCTAssertEqual(LanguagePreferences.override(in: suite), .chinese)

        LanguagePreferences.setOverride(.english, in: suite)
        XCTAssertEqual(LanguagePreferences.override(in: suite), .english)

        LanguagePreferences.setOverride(nil, in: suite)
        XCTAssertNil(LanguagePreferences.override(in: suite))
    }

    func testDisplayNamesAreSelfDescribing() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.chinese.displayName, "中文")
    }

    // MARK: - Lookup

    func testTwoStringLookup() {
        XCTAssertEqual(L("Download", "下载", language: .english), "Download")
        XCTAssertEqual(L("Download", "下载", language: .chinese), "下载")
    }

    func testFormattersUseTheChosenLocale() {
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en_US")
        XCTAssertEqual(AppLanguage.chinese.locale.language.languageCode?.identifier, "zh")
        XCTAssertEqual(AppLanguage.chinese.locale.region?.identifier, "CN")
    }

    // MARK: - Localised errors

    func testPlatformNameIsLocalised() {
        let douyin = URL(string: "https://v.douyin.com/abc")!
        XCTAssertEqual(LinkResolver.localizedPlatformName(for: douyin, language: .english), "Douyin")
        XCTAssertEqual(LinkResolver.localizedPlatformName(for: douyin, language: .chinese), "抖音")
    }

    func testUnsupportedPlatformErrorMentionsTheChineseName() {
        let error = ResolveError.unsupportedPlatform("抖音")
        XCTAssertTrue(error.errorDescription?.contains("抖音") == true)
    }
}
