import SwiftUI

@main
struct DownloadKitApp: App {
    @State private var library = LibraryStore()
    @State private var downloads = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(downloads)
                .preferredColorScheme(.dark)
                .task {
                    downloads.attach(library: library)
                    #if DEBUG
                    SmokeTest.runIfRequested(library: library, downloads: downloads)
                    #endif
                }
        }
    }
}
