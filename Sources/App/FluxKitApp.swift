import SwiftUI
import UIKit

@main
struct FluxKitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var library = LibraryStore.shared
    @State private var downloads = DownloadManager.shared
    @State private var language = LanguageStore.shared
    @State private var settings = AppSettings.shared
    @State private var network = NetworkMonitor.shared
    @State private var podcasts = PodcastStore.shared
    @State private var pro = ProStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(downloads)
                .environment(language)
                .environment(settings)
                .environment(network)
                .environment(podcasts)
                .environment(pro)
                .preferredColorScheme(.dark)
                .task {
                    // Reclaim media files no record points at (left behind by an interrupted or
                    // restarted download). Detached + age-guarded so in-flight scratch files and
                    // files the user is watching right now are never touched.
                    let referenced = library.referencedMediaFileNames
                    Task.detached(priority: .utility) {
                        let freed = MediaSweep.sweep(
                            in: AppPaths.downloads,
                            referenced: referenced
                        )
                        if freed > 0 {
                            NSLog("SWEEP: reclaimed %lld bytes of orphaned media", freed)
                        }
                    }
                }
                #if DEBUG
                .task {
                    // Simulates the share extension writing into the App Group.
                    if let link = ProcessInfo.processInfo.environment["INBOX_PUSH"] {
                        SharedInbox.push(link)
                        NSLog("INBOX: pushed \(link) (pending=\(SharedInbox.pendingCount))")
                    }
                    // UI tests can't write to the pasteboard the app will read (iOS gates
                    // cross-process reads), so they seed it from inside the app instead.
                    if let seed = ProcessInfo.processInfo.environment["PASTE_SEED"] {
                        UIPasteboard.general.string = seed
                    }
                    // Same code path as the globe menu, for screenshots and UI tests.
                    if let forced = ProcessInfo.processInfo.environment["SET_LANGUAGE"],
                       let option = AppLanguage(rawValue: forced) {
                        language.set(option)
                    }
                    DebugSeed.seedIfRequested(library: library)

                    // Screenshot / QA hook: subscribe to a feed before the UI appears.
                    if let feed = ProcessInfo.processInfo.environment["SEED_PODCAST_FEED"],
                       !PodcastStore.shared.feeds.contains(where: { $0.feedURL.absoluteString == feed }) {
                        _ = try? await PodcastStore.shared.addFeed(from: feed)
                    }
                    SmokeTest.runIfRequested(library: library, downloads: downloads)
                }
                #endif
        }
    }
}
