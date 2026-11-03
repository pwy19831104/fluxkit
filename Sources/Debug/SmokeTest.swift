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
            let media = try await LinkResolver().resolve(input: url)
            NSLog("SMOKE: resolved kind=\(media.kind.rawValue) url=\(media.url.absoluteString) title=\(media.title ?? "-") len=\(media.contentLength ?? -1)")
            downloads.start(media)
            for _ in 0..<180 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let record = library.records.first(where: { $0.remoteURL == media.url }) else { continue }
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
}
#endif
