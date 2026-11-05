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
}
