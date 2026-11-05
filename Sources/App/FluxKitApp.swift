import SwiftUI

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
                #if DEBUG
                .task {
                    // Simulates the share extension writing into the App Group.
                    if let link = ProcessInfo.processInfo.environment["INBOX_PUSH"] {
                        SharedInbox.push(link)
                        NSLog("INBOX: pushed \(link) (pending=\(SharedInbox.pendingCount))")
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
