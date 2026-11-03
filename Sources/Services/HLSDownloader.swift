import AVFoundation
import CommonCrypto
import Foundation

enum HLSError: LocalizedError {
    case emptyPlaylist
    case unsupported(String)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return "That stream playlist is empty."
        case .unsupported(let detail):
            return "This stream isn't supported: \(detail)"
        case .decryptionFailed:
            return "This stream is encrypted and couldn't be decoded."
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

    private struct MediaPlaylist {
        var url: URL
        var audioURL: URL?
    }

    // MARK: - Entry point

    /// - Returns: the file name written inside `AppPaths.downloads`.
    func download(playlistURL: URL,
                  recordID: UUID,
                  fileName: @escaping (String) -> String,
                  progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> String {

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
        var reported: Int64 = 0
        _ = try await stitch(videoSegments, into: videoFile) { delta in
            reported += delta
            progress(reported, expected > 0 ? expected : reported)
        }

        var audioFile: URL?
        if !audioSegments.isEmpty {
            let file = AppPaths.temporary.appendingPathComponent("\(recordID.uuidString)-audio.ts")
            do {
                _ = try await stitch(audioSegments, into: file) { _ in }
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
                return finalName
            } catch {
                NSLog("HLS fMP4 move failed: \(error.localizedDescription)")
            }
        }

        // 2. Mux video (+ audio) into a single MP4.
        if let name = await exportMP4(video: videoFile, audio: audioFile, finalName: fileName) {
            try? FileManager.default.removeItem(at: videoFile)
            if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
            return name
        }

        // 3. Fall back to the raw concatenated file (playable by AVPlayer on device).
        let fallbackName = fileName(isFragmentedMP4 ? "mp4" : "ts")
        let destination = AppPaths.mediaURL(fileName: fallbackName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: videoFile, to: destination)
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
        return fallbackName
    }

    // MARK: - Segment pipeline

    /// Downloads segments with a small amount of concurrency and writes them in order.
    @discardableResult
    private func stitch(_ segments: [Segment], into fileURL: URL,
                        onProgress: @escaping (Int64) -> Void) async throws -> Int64 {
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }

        // Pre-fetch encryption keys so the parallel workers don't duplicate requests.
        var keys: [URL: Data] = [:]
        for segment in segments {
            guard let key = segment.key, key.method.uppercased() == "AES-128",
                  let uri = key.uri, keys[uri] == nil else { continue }
            keys[uri] = try await fetchRaw(uri)
        }

        let batchSize = 6
        var total: Int64 = 0
        var index = 0

        while index < segments.count {
            try Task.checkCancellation()
            let end = min(index + batchSize, segments.count)
            let batch = Array(segments[index..<end])

            let datas = try await withThrowingTaskGroup(of: (Int, Data).self) { group -> [Data] in
                for (offset, segment) in batch.enumerated() {
                    group.addTask { (offset, try await self.fetchSegment(segment, keys: keys)) }
                }
                var collected = [(Int, Data)]()
                for try await result in group { collected.append(result) }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }

            for data in datas {
                try handle.write(contentsOf: data)
                total += Int64(data.count)
                onProgress(Int64(data.count))
            }
            index = end
        }
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
        if segments.allSatisfy({ $0.byteRange != nil }) {
            return segments.reduce(0) { $0 + ($1.byteRange?.length ?? 0) }
        }
        guard let first = segments.first, let size = try? await contentLength(first.url) else { return 0 }
        return size * Int64(segments.count)
    }

    // MARK: - Playlist fetching

    private func resolveMediaPlaylist(from url: URL) async throws -> MediaPlaylist {
        let (text, finalURL) = try await fetchText(url)
        guard text.contains("#EXTM3U") else { throw HLSError.unsupported("not an HLS playlist") }

        guard text.contains("#EXT-X-STREAM-INF") else {
            return MediaPlaylist(url: finalURL, audioURL: nil)
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

        return MediaPlaylist(url: best.url, audioURL: audioURL)
    }

    private func loadSegments(from url: URL) async throws -> (segments: [Segment], isFragmentedMP4: Bool) {
        let (text, finalURL) = try await fetchText(url)
        guard text.contains("#EXTM3U") else { throw HLSError.unsupported("not an HLS playlist") }

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
                    pendingInit = Segment(url: mapURL, byteRange: nil, key: nil, sequence: -1)
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
