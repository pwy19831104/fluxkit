import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
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
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Theme.background)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
