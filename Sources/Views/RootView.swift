import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LanguageStore.self) private var language
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = RootView.initialTab
    @State private var pendingLink: String?

    static var initialTab: Tab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SHOW_TAB"] {
        case "downloads": return .downloads
        case "library": return .library
        case "podcasts": return .podcasts
        case "settings": return .settings
        default: return .home
        }
        #else
        return .home
        #endif
    }

    enum Tab: Hashable { case home, downloads, podcasts, library, settings }

    private var activeCount: Int { library.active.count }

    /// `fluxkit://open?url=<percent-encoded link>`
    static func incomingLink(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "fluxkit" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = items.first(where: { $0.name == "url" })?.value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Links handed over by the share extension (`SharedInbox`). One at a time, so the user can
    /// review each preview; `onChange(of: pendingLink)` calls back here once HomeView has consumed
    /// the previous one, which is what lets a burst of shares drain instead of piling up.
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
                .tabItem { Label(L("Download", "下载"), systemImage: "arrow.down.circle") }
                .tag(Tab.home)

            DownloadsView()
                .tabItem { Label(L("Downloads", "任务"), systemImage: "square.stack.3d.down.right") }
                .badge(activeCount)
                .tag(Tab.downloads)

            PodcastsView()
                .tabItem { Label(L("Podcasts", "播客"), systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.podcasts)

            LibraryView()
                .tabItem { Label(L("Library", "片库"), systemImage: "play.rectangle.on.rectangle") }
                .tag(Tab.library)

            SettingsView()
                .tabItem { Label(L("Settings", "设置"), systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        // Rebuild the tab content when the language changes so every `L(…)` picks up the new copy.
        .id(language.language)
        .onOpenURL { url in
            guard let link = Self.incomingLink(from: url) else { return }
            selection = .home
            pendingLink = link
        }
        .onAppear(perform: drainSharedInbox)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                drainSharedInbox()
            } else if phase == .background {
                // Don't lose the last few progress updates to the save debounce.
                library.saveNow()
            }
        }
        .onChange(of: pendingLink) { _, newValue in
            if newValue == nil { drainSharedInbox() }
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
