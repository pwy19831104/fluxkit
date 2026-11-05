import Foundation

/// Minimal WebVTT reader used for subtitle renditions downloaded from HLS.
enum WebVTTParser {

    /// Parses one WebVTT document. `offset` shifts every cue (seconds).
    static func parse(_ text: String, offset: Double = 0) -> [SubtitleCue] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var cues: [SubtitleCue] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1

            if line.isEmpty || line.hasPrefix("WEBVTT") || line.hasPrefix("NOTE")
                || line.hasPrefix("STYLE") || line.hasPrefix("REGION") {
                continue
            }
            guard line.contains("-->") else { continue }
            guard let timing = parseTiming(line) else { continue }

            var payload: [String] = []
            while index < lines.count {
                let next = lines[index]
                if next.trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                    break
                }
                payload.append(next)
                index += 1
            }

            let text = clean(payload.joined(separator: "\n"))
            guard !text.isEmpty, timing.end > timing.start else { continue }
            cues.append(
                SubtitleCue(
                    start: timing.start + offset,
                    end: timing.end + offset,
                    text: text
                )
            )
        }
        return cues
    }

    /// Reads `X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:900000` (used per HLS segment).
    static func timestampMapOffset(in text: String) -> Double? {
        guard let localRange = text.range(of: "X-TIMESTAMP-MAP=") else { return nil }
        let header = text[localRange.upperBound...].prefix(200)
        guard let localPart = header.range(of: "LOCAL:"),
              let mpegPart = header.range(of: "MPEGTS:") else { return nil }

        let localText = header[localPart.upperBound..<mpegPart.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: ", \n"))
        let mpegText = header[mpegPart.upperBound...]
            .prefix { $0.isNumber }
        guard let local = parseTimestamp(localText), let mpeg = Double(mpegText) else { return nil }
        return (mpeg / 90_000) - local
    }

    /// Concatenates HLS subtitle segments, applying each segment's timestamp map.
    static func merge(segments: [String]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for segment in segments {
            let offset = timestampMapOffset(in: segment) ?? 0
            cues.append(contentsOf: parse(segment, offset: offset))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func document(from cues: [SubtitleCue]) -> String {
        var lines = ["WEBVTT", ""]
        for cue in cues {
            lines.append("\(timestamp(cue.start)) --> \(timestamp(cue.end))")
            lines.append(cue.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private struct Timing {
        var start: Double
        var end: Double
    }

    private static func parseTiming(_ line: String) -> Timing? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        guard let start = parseTimestamp(startText), let end = parseTimestamp(endText) else { return nil }
        return Timing(start: start, end: end)
    }

    static func parseTimestamp(_ text: String) -> Double? {
        let raw = text.trimmingCharacters(in: .whitespaces)
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var seconds: Double = 0
        if parts.count == 3 {
            guard let hours = Double(parts[0]), let minutes = Double(parts[1]),
                  let secs = Double(parts[2].replacingOccurrences(of: ",", with: ".")) else { return nil }
            seconds = hours * 3600 + minutes * 60 + secs
        } else {
            guard let minutes = Double(parts[0]),
                  let secs = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
            seconds = minutes * 60 + secs
        }
        return seconds
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let secs = total - Double(hours * 3600 + minutes * 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }

    private static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
