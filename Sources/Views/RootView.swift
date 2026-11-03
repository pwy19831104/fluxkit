import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = RootView.initialTab
    @State private var pendingLink: String?

    static var initialTab: Tab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SHOW_TAB"] {
        case "downloads": return .downloads
        case "library": return .library
        default: return .home
        }
        #else
        return .home
        #endif
    }

    enum Tab: Hashable { case home, downloads, library }

    private var activeCount: Int { library.active.count }

    /// `downloadkit://open?url=<percent-encoded link>`
    static func incomingLink(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "downloadkit" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = items.first(where: { $0.name == "url" })?.value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Links handed over by the share extension (`SharedInbox`) take priority over nothing:
    /// we only consume one at a time so the user can review each preview.
    private func drainSharedInbox() {
        guard pendingLink == nil else { return }
        #if DEBUG
        NSLog("INBOX: available=\(SharedInbox.isAvailable) defaults=\(SharedInbox.defaults != nil) pending=\(SharedInbox.pendingCount)")
        #endif
        guard let link = SharedInbox.popNewest() else { return }
        selection = .home
        pendingLink = link
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(pendingLink: $pendingLink)
                .tabItem { Label("Download", systemImage: "arrow.down.circle") }
                .tag(Tab.home)

            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "square.stack.3d.down.right") }
                .badge(activeCount)
                .tag(Tab.downloads)

            LibraryView()
                .tabItem { Label("Library", systemImage: "play.rectangle.on.rectangle") }
                .tag(Tab.library)
        }
        .tint(Theme.accent)
        .onOpenURL { url in
            guard let link = Self.incomingLink(from: url) else { return }
            selection = .home
            pendingLink = link
        }
        .onAppear(perform: drainSharedInbox)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { drainSharedInbox() }
        }
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Theme.background)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
