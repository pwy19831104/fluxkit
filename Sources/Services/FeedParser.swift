import Foundation

/// Minimal RSS 2.0 / Atom feed reader for podcast feeds.
///
/// It only cares about what FluxKit can download: the episode enclosure URL plus
/// a title, artwork and a few display fields. No third-party dependencies.
enum FeedParserError: LocalizedError {
    case notAFeed
    case noEpisodes

    var errorDescription: String? {
        switch self {
        case .notAFeed:
            return L("That doesn't look like a podcast feed.", "这看起来不是一个播客订阅源。")
        case .noEpisodes:
            return L("This feed has no downloadable episodes.", "这个订阅源里没有可下载的节目。")
        }
    }
}

enum FeedParser {

    /// Quick check used before paying for a full parse.
    static func looksLikeFeedText(_ text: String) -> Bool {
        let head = text.prefix(4096).lowercased()
        guard head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf") else {
            return false
        }
        return head.contains("<item") || head.contains("<entry") || head.contains("<channel")
    }

    static func looksLikeFeed(contentType: String?, url: URL) -> Bool {
        let type = contentType?.lowercased() ?? ""
        if type.contains("rss") || type.contains("atom") || type.contains("xml") {
            return true
        }
        switch url.pathExtension.lowercased() {
        case "rss", "atom", "xml": return true
        default: return false
        }
    }

    static func parse(text: String, feedURL: URL) throws -> PodcastFeed {
        guard looksLikeFeedText(text) else { throw FeedParserError.notAFeed }
        let delegate = Delegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), delegate.isFeed else { throw FeedParserError.notAFeed }
        guard !delegate.episodes.isEmpty else { throw FeedParserError.noEpisodes }

        let title = delegate.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = delegate.episodes.sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
        return PodcastFeed(
            title: title.isEmpty ? (feedURL.host ?? L("Podcast", "播客")) : FeedParser.clean(title),
            author: delegate.feedAuthor.map(FeedParser.clean),
            artworkURL: delegate.feedArtwork,
            feedURL: feedURL,
            episodes: sorted
        )
    }

    static func parse(data: Data, feedURL: URL) throws -> PodcastFeed {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return try parse(text: text, feedURL: feedURL)
    }

    // MARK: - XML

    private final class Delegate: NSObject, XMLParserDelegate {
        var isFeed = false
        var feedTitle = ""
        var feedAuthor: String?
        var feedArtwork: URL?
        var episodes: [PodcastEpisode] = []

        private var inItem = false
        private var buffer = ""
        private var episodeTitle = ""
        private var episodeDate: Date?
        private var episodeDuration: Double?
        private var episodeArtwork: URL?
        private var enclosureURL: URL?
        private var enclosureType: String?
        private var enclosureLength: Int64?

        private static let rfc822Formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm:ss Z",
        ]

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            buffer = ""
            switch elementName.lowercased() {
            case "rss", "feed", "rdf:rdf":
                isFeed = true
            case "item", "entry":
                inItem = true
                episodeTitle = ""
                episodeDate = nil
                episodeDuration = nil
                episodeArtwork = nil
                enclosureURL = nil
                enclosureType = nil
                enclosureLength = nil
            case "enclosure", "media:content":
                guard inItem else { break }
                if let raw = attributeDict["url"], let url = URL(string: raw) {
                    let type = attributeDict["type"]?.lowercased()
                    // `media:content` is only a fallback for audio/video payloads.
                    if elementName.lowercased() == "enclosure" || type?.hasPrefix("audio/") == true
                        || type?.hasPrefix("video/") == true {
                        enclosureURL = url
                        enclosureType = attributeDict["type"]
                        if let length = Int64(attributeDict["length"] ?? ""), length > 0 {
                            enclosureLength = length
                        }
                    }
                }
            case "link":
                guard inItem else { break }
                if attributeDict["rel"]?.lowercased() == "enclosure",
                   let raw = attributeDict["href"], let url = URL(string: raw) {
                    enclosureURL = url
                    enclosureType = attributeDict["type"]
                    if let length = Int64(attributeDict["length"] ?? ""), length > 0 {
                        enclosureLength = length
                    }
                }
            case "itunes:image", "image":
                if let raw = attributeDict["href"] ?? attributeDict["url"],
                   let url = URL(string: raw) {
                    if inItem { episodeArtwork = url } else if feedArtwork == nil { feedArtwork = url }
                }
            case "itunes:author", "author", "name":
                break
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName.lowercased() {
            case "title":
                if inItem { episodeTitle = text } else if feedTitle.isEmpty { feedTitle = text }
            case "itunes:author":
                if inItem || text.isEmpty { break }
                if feedAuthor == nil { feedAuthor = text }
            case "author":
                if !inItem, feedAuthor == nil { feedAuthor = text }
            case "itunes:duration":
                if inItem { episodeDuration = Self.seconds(from: text) ?? episodeDuration }
            case "pubdate", "published", "updated":
                if inItem, episodeDate == nil { episodeDate = Self.date(from: text) }
            case "url":
                if !inItem, let url = URL(string: text), feedArtwork == nil { feedArtwork = url }
            case "item", "entry":
                finishEpisode()
            default:
                break
            }
            buffer = ""
        }

        private func finishEpisode() {
            defer {
                inItem = false
                episodeTitle = ""
                episodeDate = nil
                episodeDuration = nil
                episodeArtwork = nil
                enclosureURL = nil
                enclosureType = nil
                enclosureLength = nil
            }
            guard let enclosureURL else { return }
            let cleaned = FeedParser.clean(episodeTitle)
            let title = cleaned.isEmpty
                ? (enclosureURL.deletingPathExtension().lastPathComponent)
                : cleaned
            episodes.append(
                PodcastEpisode(
                    title: title,
                    publishedAt: episodeDate,
                    duration: episodeDuration,
                    byteLength: enclosureLength,
                    enclosureURL: enclosureURL,
                    mimeType: enclosureType,
                    artworkURL: episodeArtwork
                )
            )
        }

        static func seconds(from text: String) -> Double? {
            let parts = text.split(separator: ":").map { Double($0) }
            guard !parts.contains(nil) else { return nil }
            let values = parts.compactMap { $0 }
            switch values.count {
            case 1: return values[0]
            case 2: return values[0] * 60 + values[1]
            case 3: return values[0] * 3600 + values[1] * 60 + values[2]
            default: return nil
            }
        }

        static func date(from text: String) -> Date? {
            for format in rfc822Formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                if let date = formatter.date(from: text) { return date }
            }
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: text)
        }
    }

    /// Strips HTML tags and decodes the handful of entities podcast titles use.
    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
