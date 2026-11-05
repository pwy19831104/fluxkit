import CoreMedia
import Foundation

struct SubtitleCue: Equatable, Identifiable {
    let id = UUID()
    var start: Double
    var end: Double
    var text: String

    var startTime: CMTime { CMTime(seconds: start, preferredTimescale: 600) }
}

/// A downloaded external subtitle file (usually WebVTT extracted from an HLS rendition).
struct ExternalSubtitle: Identifiable, Equatable {
    var id: String { url.lastPathComponent }
    var languageCode: String
    var label: String
    var url: URL
    var cues: [SubtitleCue] = []

    var isLoaded: Bool { !cues.isEmpty }
}
