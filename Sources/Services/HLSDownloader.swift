import AVFoundation
import CommonCrypto
import Foundation

enum HLSError: LocalizedError {
    case emptyPlaylist
    case liveStream
    case unsupported(String)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return L("That stream playlist is empty.", "这个流播放列表是空的。")
        case .liveStream:
            return L("Live streams aren't supported yet. Try a link to a finished video.",
                     "暂不支持直播流，换一个已结束的视频链接。")
        case .unsupported(let detail):
            #if DEBUG
            NSLog("HLS unsupported: \(detail)")
            #endif
            return L("This video can't be downloaded. Try a different link.",
                     "这个视频无法下载，换一个链接试试。")
        case .decryptionFailed:
            return L("This stream is encrypted and couldn't be decoded.", "这个流已加密，无法解密。")
        }
    }
}

/// Downloads an HLS stream by fetching every segment, stitching them together and
/// remuxing the result into a single `.mp4` (falling back to the raw `.ts`).
struct HLSDownloader: Sendable {

    private let session: URLSession
    private let headers: [String: String]

    init(headers: [String: String] = [:]) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = ["User-Agent": LinkResolver.userAgent]
            .merging(headers, uniquingKeysWith: { $1 })
        self.headers = headers
        self.session = URLSession(configuration: config)
    }

    // MARK: - Data structures

    private struct KeyInfo {
        var method: String
        var uri: URL?
        var iv: Data?
    }

    private struct Segment {
        var url: URL
        var byteRange: (offset: Int64, length: Int64)?
        var key: KeyInfo?
        var sequence: Int
    }

    struct SubtitleRendition {
        var language: String
        var url: URL
    }

    private struct MediaPlaylist {
        var url: URL
        var audioURL: URL?
        var subtitles: [SubtitleRendition]
    }

    // MARK: - Entry point

    /// - Returns: the file name written inside `AppPaths.downloads`.
    func download(playlistURL: URL,
                  recordID: UUID,
                  fileName: @escaping (String) -> String,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> String {

        let shop = AppPaths.hlsWork(recordID: recordID)
        var completed = false
        defer {
            if completed { try? FileManager.default.removeItem(at: shop) }
        }

        let playlist = try await resolveMediaPlaylist(from: playlistURL)
        let (videoSegments, isFragmentedMP4) = try await loadSegments(from: playlist.url)
        guard !videoSegments.isEmpty else { throw HLSError.emptyPlaylist }

        var audioSegments: [Segment] = []
        if let audioURL = playlist.audioURL {
            audioSegments = (try? await loadSegments(from: audioURL).0) ?? []
        }

        let expected = try await estimatedSize(of: videoSegments)
        if expected > 0 { progress(0, expected) }

        let videoFile = AppPaths.temporary.appendingPathComponent("\(recordID.uuidString)-video.ts")
        _ = try await stitch(videoSegments, into: videoFile, work: shop, prefix: "v") { bytes in
            progress(bytes, expected > 0 ? expected : bytes)
        }

        var audioFile: URL?
        if !audioSegments.isEmpty {
            let file = AppPaths.temporary.appendingPathComponent("\(recordID.uuidString)-audio.ts")
            do {
                _ = try await stitch(audioSegments, into: file, work: shop, prefix: "a")
                audioFile = file
            } catch {
                NSLog("HLS audio track failed: \(error.localizedDescription)")
            }
        }

        // 1. fMP4 segments are already a valid fragmented MP4 once concatenated.
        if isFragmentedMP4, audioSegments.isEmpty {
            let finalName = fileName("mp4")
            let destination = AppPaths.mediaURL(fileName: finalName)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: videoFile, to: destination)
                await downloadSubtitles(playlist.subtitles, recordID: recordID)
                completed = true
                return finalName
            } catch {
                NSLog("HLS fMP4 move failed: \(error.localizedDescription)")
            }
        }

        // 2. Mux video (+ audio) into a single MP4.
        if let name = await exportMP4(video: videoFile, audio: audioFile, finalName: fileName) {
            try? FileManager.default.removeItem(at: videoFile)
            if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
            await downloadSubtitles(playlist.subtitles, recordID: recordID)
            completed = true
            return name
        }

        // 3. Fall back to the raw concatenated file (playable by AVPlayer on device).
        let fallbackName = fileName(isFragmentedMP4 ? "mp4" : "ts")
        let destination = AppPaths.mediaURL(fileName: fallbackName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: videoFile, to: destination)
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
        await downloadSubtitles(playlist.subtitles, recordID: recordID)
        completed = true
        return fallbackName
    }

    // MARK: - Segment pipeline

    /// Downloads segments with a small amount of concurrency.
    ///
    /// Each segment is written to its own file under `work`, so a paused/crashed job can skip
    /// everything already on disk. The segments are concatenated only when the whole playlist
    /// is present.
    @discardableResult
    private func stitch(_ segments: [Segment], into fileURL: URL,
                        work: URL, prefix: String,
                        onBytes: @escaping (Int64) -> Void = { _ in }) async throws -> Int64 {
        // Pre-fetch encryption keys so the parallel workers don't duplicate requests.
        var keys: [URL: Data] = [:]
        for segment in segments {
            guard let key = segment.key, key.method.uppercased() == "AES-128",
                  let uri = key.uri, keys[uri] == nil else { continue }
            keys[uri] = try await fetchRaw(uri)
        }

        func segmentFile(_ index: Int) -> URL {
            work.appendingPathComponent("\(prefix)-\(index).seg")
        }
        func size(of url: URL) -> Int64 {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        }

        var cached: Int64 = 0
        for index in segments.indices where FileManager.default.fileExists(atPath: segmentFile(index).path) {
            cached += size(of: segmentFile(index))
        }
        if cached > 0 { onBytes(cached) }

        let batchSize = 6
        var index = 0
        while index < segments.count {
            try Task.checkCancellation()
            let end = min(index + batchSize, segments.count)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for segmentIndex in index..<end {
                    let file = segmentFile(segmentIndex)
                    guard !FileManager.default.fileExists(atPath: file.path) else { continue }
                    let segment = segments[segmentIndex]
                    group.addTask {
                        let data = try await self.fetchSegment(segment, keys: keys)
                        try data.write(to: file, options: .atomic)
                    }
                }
                try await group.waitForAll()
            }

            var done: Int64 = 0
            for segmentIndex in 0..<end {
                done += size(of: segmentFile(segmentIndex))
            }
            onBytes(done)
            index = end
        }

        // Concatenate in order.
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        var total: Int64 = 0
        for segmentIndex in segments.indices {
            let data = try Data(contentsOf: segmentFile(segmentIndex), options: .mappedIfSafe)
            try handle.write(contentsOf: data)
            total += Int64(data.count)
        }
        onBytes(total)
        return total
    }

    private func fetchSegment(_ segment: Segment, keys: [URL: Data]) async throws -> Data {
        var request = URLRequest(url: segment.url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let range = segment.byteRange {
            request.setValue("bytes=\(range.offset)-\(range.offset + range.length - 1)",
                             forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HLSError.unsupported("segment request failed (\((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }

        guard let key = segment.key else { return data }
        switch key.method.uppercased() {
        case "AES-128":
            guard let uri = key.uri, let keyData = keys[uri] else { throw HLSError.decryptionFailed }
            return try Self.decrypt(data: data, key: keyData, iv: key.iv ?? Self.sequenceIV(segment.sequence))
        case "SAMPLE-AES", "SAMPLE-AES-CTR":
            throw HLSError.unsupported("SAMPLE-AES encryption")
        default:
            return data
        }
    }

    private func estimatedSize(of segments: [Segment]) async throws -> Int64 {
        let ranged = segments.filter { $0.byteRange != nil }
        if ranged.count == segments.count, !ranged.isEmpty {
            return ranged.reduce(0) { $0 + ($1.byteRange?.length ?? 0) }
        }
        if !ranged.isEmpty {
            // Byte-range playlists (single file, many ranges): scale the known ranges.
            let total = ranged.reduce(0) { $0 + ($1.byteRange?.length ?? 0) }
            let average = Double(total) / Double(ranged.count)
            return Int64(average * Double(segments.count))
        }
        guard let first = segments.first, let size = try? await contentLength(first.url) else { return 0 }
        return size * Int64(segments.count)
    }

    // MARK: - Playlist fetching

    private func resolveMediaPlaylist(from url: URL) async throws -> MediaPlaylist {
        let (text, finalURL) = try await fetchText(url)
        guard text.contains("#EXTM3U") else { throw HLSError.unsupported("not an HLS playlist") }

        guard text.contains("#EXT-X-STREAM-INF") else {
            return MediaPlaylist(url: finalURL, audioURL: nil, subtitles: [])
        }

        var variants: [(bandwidth: Int, url: URL)] = []
        var pendingBandwidth: Int?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                let attrs = Self.attributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
                pendingBandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? 0
            } else if !line.isEmpty, !line.hasPrefix("#"), let bandwidth = pendingBandwidth {
                if let variantURL = URL(string: line, relativeTo: finalURL)?.absoluteURL {
                    variants.append((bandwidth, variantURL))
                }
                pendingBandwidth = nil
            }
        }

        guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
            throw HLSError.unsupported("no playable variant")
        }

        // Streams that ship audio as a separate rendition (common for Apple-style HLS).
        var audioURL: URL?
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("#EXT-X-MEDIA") {
            let attrs = Self.attributes(line)
            if (attrs["TYPE"]?.uppercased() == "AUDIO"),
               let uri = attrs["URI"],
               let resolved = URL(string: uri, relativeTo: finalURL)?.absoluteURL {
                // Prefer the default rendition, otherwise take the first one.
                if audioURL == nil || attrs["DEFAULT"]?.uppercased() == "YES" {
                    audioURL = resolved
                }
            }
        }

        return MediaPlaylist(
            url: best.url,
            audioURL: audioURL,
            subtitles: Self.subtitleRenditions(in: text, baseURL: finalURL)
        )
    }

    /// Parses `#EXT-X-MEDIA:TYPE=SUBTITLES` renditions from a master playlist.
    static func subtitleRenditions(in text: String, baseURL: URL) -> [SubtitleRendition] {
        var result: [SubtitleRendition] = []
        var seen = Set<String>()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXT-X-MEDIA") else { continue }
            let attrs = attributes(line)
            guard attrs["TYPE"]?.uppercased() == "SUBTITLES",
                  let uri = attrs["URI"],
                  let url = URL(string: uri, relativeTo: baseURL)?.absoluteURL else { continue }
            let language = attrs["LANGUAGE"] ?? attrs["NAME"] ?? "und"
            if seen.insert(language).inserted {
                result.append(SubtitleRendition(language: language, url: url))
            }
        }
        return result
    }

    /// Saves subtitle renditions next to the download as `<record-id>.<language>.vtt`.
    private func downloadSubtitles(_ renditions: [SubtitleRendition], recordID: UUID) async {
        guard !renditions.isEmpty else { return }
        AppPaths.removeSubtitles(recordID: recordID)

        for rendition in renditions {
            do {
                let (playlistText, base) = try await fetchText(rendition.url)
                var segments: [URL] = []
                for rawLine in playlistText.components(separatedBy: .newlines) {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                    if let url = URL(string: line, relativeTo: base)?.absoluteURL {
                        segments.append(url)
                    }
                }

                let cues: [SubtitleCue]
                if segments.isEmpty {
                    let offset = WebVTTParser.timestampMapOffset(in: playlistText) ?? 0
                    cues = WebVTTParser.parse(playlistText, offset: offset)
                } else {
                    var documents: [String] = []
                    for segment in segments {
                        if let (text, _) = try? await fetchText(segment) {
                            documents.append(text)
                        }
                    }
                    cues = WebVTTParser.merge(segments: documents)
                }
                guard !cues.isEmpty else { continue }
                let data = Data(WebVTTParser.document(from: cues).utf8)
                try data.write(
                    to: AppPaths.subtitleURL(recordID: recordID, language: rendition.language),
                    options: .atomic
                )
            } catch {
                NSLog("HLS subtitle \(rendition.language) failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadSegments(from url: URL) async throws -> (segments: [Segment], isFragmentedMP4: Bool) {
        let (text, finalURL) = try await fetchText(url)
        guard text.contains("#EXTM3U") else { throw HLSError.unsupported("not an HLS playlist") }
        if Self.isLivePlaylist(text) { throw HLSError.liveStream }

        var segments: [Segment] = []
        var currentKey: KeyInfo?
        var sequence = 0
        var pendingRange: (offset: Int64, length: Int64)?
        var pendingInit: Segment?

        func parseKey(_ value: String) -> KeyInfo? {
            let attrs = Self.attributes(value)
            let method = attrs["METHOD"] ?? "NONE"
            if method.uppercased() == "NONE" { return nil }
            var ivData: Data?
            if var iv = attrs["IV"] {
                if iv.lowercased().hasPrefix("0x") { iv = String(iv.dropFirst(2)) }
                ivData = Data(hexString: iv)
            }
            return KeyInfo(method: method,
                           uri: attrs["URI"].flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL },
                           iv: ivData)
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXT-X-KEY") {
                currentKey = parseKey(String(line.dropFirst("#EXT-X-KEY:".count)))
            } else if line.hasPrefix("#EXT-X-MAP") {
                let attrs = Self.attributes(String(line.dropFirst("#EXT-X-MAP:".count)))
                if let uri = attrs["URI"], let mapURL = URL(string: uri, relativeTo: finalURL)?.absoluteURL {
                    var mapRange: (offset: Int64, length: Int64)?
                    if let raw = attrs["BYTERANGE"] {
                        let parts = raw.split(separator: "@")
                        if let length = Int64(parts[0]) {
                            mapRange = (parts.count > 1 ? (Int64(parts[1]) ?? 0) : 0, length)
                        }
                    }
                    pendingInit = Segment(url: mapURL, byteRange: mapRange, key: nil, sequence: -1)
                }
            } else if line.hasPrefix("#EXT-X-BYTERANGE") {
                let value = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
                let parts = value.split(separator: "@")
                if let length = Int64(parts[0]) {
                    pendingRange = (parts.count > 1 ? (Int64(parts[1]) ?? 0) : 0, length)
                }
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE") {
                let value = String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                sequence = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("#") {
                continue
            } else if let segmentURL = URL(string: line, relativeTo: finalURL)?.absoluteURL {
                if let initSegment = pendingInit {
                    segments.append(initSegment)
                    pendingInit = nil
                }
                segments.append(Segment(url: segmentURL,
                                        byteRange: pendingRange,
                                        key: currentKey,
                                        sequence: sequence))
                pendingRange = nil
                sequence += 1
            }
        }

        let fragmented = segments.contains { segment in
            let ext = segment.url.pathExtension.lowercased()
            return ext == "m4s" || ext == "mp4" || ext == "m4v" || ext == "cmfv" || ext == "cmfa"
        }
        return (segments, fragmented)
    }

    // MARK: - Networking

    private func fetchRaw(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HLSError.unsupported("key request failed")
        }
        return data
    }

    private func fetchText(_ url: URL) async throws -> (text: String, url: URL) {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HLSError.unsupported("playlist request failed")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw HLSError.unsupported("playlist encoding")
        }
        return (text, response.url ?? url)
    }

    private func contentLength(_ url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let value = http.value(forHTTPHeaderField: "Content-Length"),
              let length = Int64(value) else { return nil }
        return length
    }

    // MARK: - Export

    private func exportMP4(video: URL, audio: URL?, finalName: @escaping (String) -> String) async -> String? {
        let videoAsset = AVURLAsset(url: video)
        var asset: AVAsset = videoAsset
        if let audio, let composed = await Self.compose(video: videoAsset, audio: AVURLAsset(url: audio)) {
            asset = composed
        }

        let name = finalName("mp4")
        let destination = AppPaths.mediaURL(fileName: name)
        try? FileManager.default.removeItem(at: destination)

        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            if #available(iOS 18.0, *) {
                do {
                    try await exporter.export(to: destination, as: .mp4)
                    return name
                } catch {
                    NSLog("HLS export (\(preset)) failed: \(error) code=\((error as NSError).code)")
                    try? FileManager.default.removeItem(at: destination)
                }
            } else {
                let exportSession = SendableExportSession(exporter)
                exporter.outputURL = destination
                exporter.outputFileType = .mp4
                exporter.shouldOptimizeForNetworkUse = true
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        exporter.exportAsynchronously {
                            let finished = exportSession.session
                            if finished.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: finished.error ?? HLSError.unsupported("export"))
                            }
                        }
                    }
                    return name
                } catch {
                    NSLog("HLS export (\(preset)) failed: \(error) code=\((error as NSError).code)")
                    try? FileManager.default.removeItem(at: destination)
                }
            }
        }
        return nil
    }

    private static func compose(video: AVURLAsset, audio: AVURLAsset) async -> AVMutableComposition? {
        let composition = AVMutableComposition()
        do {
            let videoDuration = try await video.load(.duration)
            if let videoTrack = try await video.loadTracks(withMediaType: .video).first,
               let target = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                try target.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                           of: videoTrack, at: .zero)
            }
            if let audioTrack = try await audio.loadTracks(withMediaType: .audio).first,
               let target = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audio.load(.duration)
                let shortest = CMTimeMinimum(videoDuration, audioDuration)
                try target.insertTimeRange(CMTimeRange(start: .zero, duration: shortest),
                                           of: audioTrack, at: .zero)
            }
            return composition
        } catch {
            NSLog("HLS audio mux failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Crypto helpers

    private static func sequenceIV(_ sequence: Int) -> Data {
        var value = UInt32(bitPattern: Int32(sequence)).bigEndian
        var iv = Data(repeating: 0, count: 16)
        withUnsafeBytes(of: &value) { iv.replaceSubrange(12..<16, with: $0) }
        return iv
    }

    static func decrypt(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == 16 else { throw HLSError.decryptionFailed }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outBuffer in
            data.withUnsafeBytes { inBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBuffer.baseAddress, key.count,
                                ivBuffer.baseAddress,
                                inBuffer.baseAddress, data.count,
                                outBuffer.baseAddress, outBuffer.count,
                                &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw HLSError.decryptionFailed }
        return output.prefix(moved)
    }

    // MARK: - Attribute parsing

    /// A media playlist without `#EXT-X-ENDLIST` is live/event unless it explicitly says VOD.
    static func isLivePlaylist(_ text: String) -> Bool {
        !text.contains("#EXT-X-ENDLIST") && !text.contains("#EXT-X-PLAYLIST-TYPE:VOD")
    }

    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([A-Z0-9-]+)=(\"([^\"]*)\"|[^,]*)") else { return result }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            let valueGroup = match.range(at: 3).location != NSNotFound ? 3 : 2
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: valueGroup), in: text) else { continue }
            result[String(text[keyRange])] = String(text[valueRange])
        }
        return result
    }
}

/// `AVAssetExportSession`'s legacy completion API is `@Sendable` but the object isn't
/// marked `Sendable`; this box keeps the compiler (and Swift 6 mode) happy.
private struct SendableExportSession: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

extension Data {
    init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("0x") { cleaned = String(cleaned.dropFirst(2)) }
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
