import XCTest
@testable import FluxKit

final class WebVTTTests: XCTestCase {

    func testParsesBasicCues() {
        let vtt = """
            WEBVTT

            NOTE this is a comment

            1
            00:00:01.000 --> 00:00:03.500
            Hello <i>world</i>

            00:04.000 --> 00:05.250
            Second &amp; last
            """
        let cues = WebVTTParser.parse(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(cues[1].start, 4, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "Second & last")
    }

    func testAppliesSegmentTimestampMap() {
        let segment = """
            WEBVTT
            X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:900000

            00:00:01.000 --> 00:00:02.000
            Off by ten
            """
        let cues = WebVTTParser.merge(segments: [segment])
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].start, 11, accuracy: 0.01)
    }

    func testDocumentRoundTrips() {
        let cues = [
            SubtitleCue(start: 1.5, end: 3, text: "One"),
            SubtitleCue(start: 65, end: 67.25, text: "Two"),
        ]
        let text = WebVTTParser.document(from: cues)
        let parsed = WebVTTParser.parse(text)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].start, 1.5, accuracy: 0.01)
        XCTAssertEqual(parsed[1].start, 65, accuracy: 0.01)
    }

    func testParsesHLSSubtitleRenditions() {
        let master = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subtitles/eng.m3u8"
            #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Français",LANGUAGE="fr",URI="subtitles/fra.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Audio",URI="audio.m3u8"
            """
        let renditions = HLSDownloader.subtitleRenditions(
            in: master,
            baseURL: URL(string: "https://example.com/master.m3u8")!
        )
        XCTAssertEqual(renditions.map(\.language), ["en", "fr"])
        XCTAssertEqual(renditions[0].url.absoluteString, "https://example.com/subtitles/eng.m3u8")
    }

    // MARK: - X-TIMESTAMP-MAP key order

    /// Apple's HLS example streams put MPEGTS first. Assuming the RFC example order crashed the
    /// whole download job (invalid `Range`), so both orders must be covered.
    func testTimestampMapAcceptsBothKeyOrders() {
        let mpegtsFirst = """
            WEBVTT
            X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000

            1
            00:00:01.000 --> 00:00:02.000
            Hello
            """
        let localFirst = """
            WEBVTT
            X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:900000

            1
            00:00:01.000 --> 00:00:02.000
            Hello
            """
        XCTAssertEqual(WebVTTParser.timestampMapOffset(in: mpegtsFirst) ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(WebVTTParser.timestampMapOffset(in: localFirst) ?? -1, 10, accuracy: 0.001)
    }

    func testTimestampMapHandlesNonZeroLocalTime() {
        // LOCAL 00:00:10 with MPEGTS 900000 (10s) cancels out to a zero offset.
        let text = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:10.000\n"
        XCTAssertEqual(WebVTTParser.timestampMapOffset(in: text) ?? -1, 0, accuracy: 0.001)

        // LOCAL 00:00:00 with MPEGTS 1_800_000 (20s) shifts cues by 20 seconds.
        let shifted = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:1800000,LOCAL:00:00:00.000\n"
        XCTAssertEqual(WebVTTParser.timestampMapOffset(in: shifted) ?? -1, 20, accuracy: 0.001)
    }

    func testTimestampMapRejectsMalformedHeadersWithoutCrashing() {
        let cases = [
            "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:900000\n",            // LOCAL missing
            "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000\n",         // MPEGTS missing
            "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:,MPEGTS:\n",            // empty values
            "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:abc,LOCAL:00:00:00.000\n", // non-numeric MPEGTS
            "WEBVTT\nX-TIMESTAMP-MAP=\n",                          // empty header
            "WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nHi\n",   // no map at all
        ]
        for text in cases {
            XCTAssertNil(WebVTTParser.timestampMapOffset(in: text), "should not parse: \(text)")
            // Merging must also survive it: a segment without a usable map falls back to offset 0.
            XCTAssertNoThrow(WebVTTParser.merge(segments: [text]))
        }
    }

    func testMergeAppliesOffsetsPerSegmentRegardlessOfKeyOrder() {
        let first = """
            WEBVTT
            X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000

            00:00:01.000 --> 00:00:02.000
            First
            """
        let second = """
            WEBVTT
            X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:1800000

            00:00:01.000 --> 00:00:02.000
            Second
            """
        let cues = WebVTTParser.merge(segments: [first, second])
        XCTAssertEqual(cues.map(\.text), ["First", "Second"])
        XCTAssertEqual(cues[0].start, 11, accuracy: 0.001)
        XCTAssertEqual(cues[1].start, 21, accuracy: 0.001)
    }
}
