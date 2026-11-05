#if DEBUG
import Foundation

/// Development-only harness: `simctl launch ... --smoke-test` with `SMOKE_URLS` env var
/// resolves + downloads each link and prints the outcome. Not shipped to the App Store.
enum SmokeTest {
    static func runIfRequested(library: LibraryStore, downloads: DownloadManager) {
        guard ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
        let urls = (ProcessInfo.processInfo.environment["SMOKE_URLS"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task { @MainActor in
            for url in urls { await check(url: url, library: library, downloads: downloads) }
            NSLog("SMOKE: DONE")
        }
    }

    @MainActor
    private static func check(url: String, library: LibraryStore, downloads: DownloadManager) async {
        NSLog("SMOKE: resolving \(url)")
        do {
            var media = try await LinkResolver().resolve(input: url)
            NSLog("SMOKE: resolved kind=\(media.kind.rawValue) url=\(media.url.absoluteString) title=\(media.title ?? "-") len=\(media.contentLength ?? -1)")

            if ProcessInfo.processInfo.environment["SMOKE_STALE_URL"] != nil {
                media.url = staleVariant(of: media.url)
                NSLog("SMOKE: forcing stale address \(media.url.absoluteString)")
            }

            let before = Set(library.records.map(\.id))
            downloads.start(media)

            guard let started = library.records.first(where: { !before.contains($0.id) }) else {
                NSLog("SMOKE: FAIL \(url) reason=record not created")
                return
            }
            // Track by id: a refreshed address changes `remoteURL` mid-flight.
            let recordID = started.id

            if ProcessInfo.processInfo.environment["SMOKE_PAUSE"] != nil {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let active = library.record(id: recordID) {
                    NSLog("SMOKE: pausing at \(active.bytesReceived) bytes")
                    downloads.pause(active.id)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let paused = library.record(id: active.id) {
                        NSLog("SMOKE: state after pause = \(paused.state.rawValue), resume file exists = \(FileManager.default.fileExists(atPath: AppPaths.resumeDataURL(recordID: paused.id).path))")
                        downloads.resume(paused)
                        NSLog("SMOKE: resumed")
                    }
                }
            }

            for tick in 0..<180 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let record = library.record(id: recordID) else { continue }
                if tick % 12 == 0 {
                    NSLog("SMOKE: tick \(tick) state=\(record.state.rawValue) bytes=\(record.bytesReceived)/\(record.bytesExpected) url=\(record.remoteURL.absoluteString)")
                }
                switch record.state {
                case .finished:
                    NSLog("SMOKE: PASS \(url) file=\(record.fileName ?? "-") bytes=\(record.bytesReceived) thumb=\(record.thumbnailName ?? "-") duration=\(record.duration ?? -1)")
                    return
                case .failed, .cancelled:
                    NSLog("SMOKE: FAIL \(url) reason=\(record.errorMessage ?? "-")")
                    return
                default:
                    continue
                }
            }
            NSLog("SMOKE: TIMEOUT \(url)")
        } catch {
            NSLog("SMOKE: FAIL \(url) reason=\(error.localizedDescription)")
        }
    }

    /// Rewrites a media address into one the CDN will refuse (a path that does not exist),
    /// so the automatic re-resolve path can be exercised without waiting for a real token
    /// to lapse. The page thumbnail/title are untouched.
    private static func staleVariant(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        var mutated = parts.map(String.init)
        if let index = mutated.firstIndex(where: { $0.hasPrefix("mda-") }) {
            mutated[index] = "mda-fluxkitstale00000000"
        } else {
            return url.appendingPathExtension("stale")
        }
        components.path = mutated.joined(separator: "/")
        return components.url ?? url
    }
}
#endif
