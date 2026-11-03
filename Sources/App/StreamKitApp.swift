import SwiftUI

@main
struct StreamKitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var library = LibraryStore.shared
    @State private var downloads = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(downloads)
                .preferredColorScheme(.dark)
                #if DEBUG
                .task {
                    // Simulates the share extension writing into the App Group.
                    if let link = ProcessInfo.processInfo.environment["INBOX_PUSH"] {
                        SharedInbox.push(link)
                        NSLog("INBOX: pushed \(link) (pending=\(SharedInbox.pendingCount))")
                    }
                    SmokeTest.runIfRequested(library: library, downloads: downloads)
                }
                #endif
        }
    }
}
