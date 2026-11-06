import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NetworkMonitor.self) private var network
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(LanguageStore.self) private var language
    @Environment(PodcastStore.self) private var podcasts
    @Environment(ProStore.self) private var pro

    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var showPaywall = false
    @State private var showClearTempConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    proCard
                    downloadsCard
                    podcastsCard
                    notificationsCard
                    storageCard
                    languageCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("Settings", "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings.wifiOnly) { _, _ in
                downloads.networkChanged()
            }
            .onChange(of: pro.isPro) { _, _ in
                downloads.networkChanged()
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-showPaywall") {
                    showPaywall = true
                }
                #endif
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "opml") ?? .xml, .xml]
            ) { result in
                switch result {
                case .success(let url): importOPML(url)
                case .failure(let error): importSummary = error.localizedDescription
                }
            }
            .confirmationDialog(
                L("Clear temporary files?", "清理临时文件？"),
                isPresented: $showClearTempConfirm,
                titleVisibility: .visible
            ) {
                Button(L("Clear", "清理"), role: .destructive) {
                    AppPaths.purgeTemporaryFiles()
                }
                Button(L("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(L("Downloads that already finished are not affected.",
                       "已经下载完成的文件不受影响。"))
            }
            .alert(L("Subscriptions", "订阅"), isPresented: Binding(
                get: { importSummary != nil },
                set: { if !$0 { importSummary = nil } }
            )) {
                Button(L("OK", "好"), role: .cancel) {}
            } message: {
                Text(importSummary ?? "")
            }
        }
    }

    // MARK: - Pro

    private var proCard: some View {
        card(title: "FLUXKIT PRO") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pro.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(pro.isPro ? Theme.success : Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pro.isPro
                         ? L("Pro is active", "Pro 已激活")
                         : L("Free plan", "免费版"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("settings-pro-status")
                    Text(pro.isPro
                         ? L("Thanks for supporting FluxKit.", "感谢支持 FluxKit。")
                         : L("1 download at a time. Pro adds 4-at-once and podcast auto-download.",
                             "同时 1 个下载。Pro 可 4 个并发并开启播客自动下载。"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !pro.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Text(L("Upgrade", "升级"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.brandGradient))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-pro-upgrade")
                }
            }

            if !pro.isPro {
                Divider().overlay(Theme.stroke)
                HStack {
                    Button {
                        Task { await pro.restore() }
                    } label: {
                        Text(L("Restore purchases", "恢复购买"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    if pro.isLoading { ProgressView() }
                }
            }
        }
    }

    // MARK: - Downloads

    private var downloadsCard: some View {
        card(title: L("DOWNLOADS", "下载")) {
            Toggle(isOn: Binding(
                get: { settings.wifiOnly },
                set: { settings.wifiOnly = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Wi-Fi only", "仅 Wi-Fi 下载"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(networkSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("settings-wifi-only")

            Divider().overlay(Theme.stroke)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("At the same time", "同时下载数"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Queued tasks start automatically.", "排队任务会自动开始。"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: {
                        pro.isPro ? settings.maxConcurrentDownloads : 1
                    },
                    set: { value in
                        settings.maxConcurrentDownloads = value
                        downloads.networkChanged()
                    }
                )) {
                    ForEach(1...4, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .disabled(!pro.isPro)
                .opacity(pro.isPro ? 1 : 0.55)
            }

            if !pro.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label(L("Up to 4 at once with Pro", "Pro 可同时下载 4 个"), systemImage: "lock.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            Text(L("HLS downloads keep running while the app is open; direct files also continue in the background.",
                   "HLS 下载需要 App 保持打开；直链文件在后台也会继续。"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var networkSubtitle: String {
        if !network.isConnected { return L("Offline right now", "当前没有网络") }
        if network.isOnWiFi { return L("On Wi-Fi", "已连接 Wi-Fi") }
        return settings.wifiOnly
            ? L("On cellular — downloads wait for Wi-Fi", "当前是蜂窝网络，下载会等待 Wi-Fi")
            : L("On cellular", "当前是蜂窝网络")
    }

    // MARK: - Podcasts

    private var podcastsCard: some View {
        card(title: L("PODCASTS", "播客")) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Auto-download new episodes", "自动下载新节目"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Applied when a subscribed feed refreshes.", "订阅刷新时自动下载。"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { pro.isPro ? settings.podcastAutoDownload : 0 },
                    set: { settings.podcastAutoDownload = $0 }
                )) {
                    Text(L("Off", "关闭")).tag(0)
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .disabled(!pro.isPro)
            }

            if !pro.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label(L("Auto-download is a Pro feature", "自动下载为 Pro 功能"), systemImage: "lock.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            Divider().overlay(Theme.stroke)

            HStack {
                Text(L("\(podcasts.feeds.count) subscriptions", "\(podcasts.feeds.count) 个订阅"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                ShareLink(item: podcasts.opmlDocument) {
                    Text(L("Export OPML", "导出 OPML"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityIdentifier("settings-export-opml")
                Button {
                    showImporter = true
                } label: {
                    Text(L("Import", "导入"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .disabled(isImporting)
                .accessibilityIdentifier("settings-import-opml")
            }

            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Importing feeds…", "正在导入订阅…"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func importOPML(_ url: URL) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importSummary = L("Couldn't read that file.", "无法读取这个文件。")
                return
            }
            let urls = PodcastStore.feedURLs(inOPML: data)
            guard !urls.isEmpty else {
                importSummary = L("No podcast feeds were found in that OPML file.",
                                  "这个 OPML 文件里没有播客订阅。")
                return
            }
            var added = 0
            for feedURL in urls {
                if (try? await podcasts.addFeed(from: feedURL.absoluteString)) != nil {
                    added += 1
                }
            }
            importSummary = L("Imported \(added) of \(urls.count) feeds.",
                              "已导入 \(added) / \(urls.count) 个订阅。")
        }
    }

    /// HLS jobs keep their segments and concatenated pieces in `AppPaths.temporary`; deleting them
    /// mid-flight kills the transfer.
    private var hasActiveHLSJob: Bool {
        library.active.contains { $0.kind == .hls }
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        card(title: L("NOTIFICATIONS", "通知")) {
            Toggle(isOn: Binding(
                get: { settings.notifyOnFinish },
                set: { settings.notifyOnFinish = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Download finished", "下载完成提醒"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Only while the app is in the background.", "仅在 App 处于后台时提醒。"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("settings-notify")
        }
    }

    // MARK: - Storage

    private var storageCard: some View {
        card(title: L("STORAGE", "存储")) {
            HStack {
                Text(L("Downloaded", "已下载"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Fmt.bytes(library.totalBytes))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack {
                Text(L("Free space", "可用空间"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Fmt.bytes(Self.freeSpace))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            if let warning = library.persistenceWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-persistence-warning")
            }
            Text(L("Downloads are visible in Files → On My iPhone → FluxKit → Media.",
                   "下载文件会出现在「文件」App → 我的 iPhone → FluxKit → Media。"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showClearTempConfirm = true
            } label: {
                Label(L("Clear temporary files", "清理临时文件"), systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(hasActiveHLSJob)
            .opacity(hasActiveHLSJob ? 0.5 : 1)
            .accessibilityIdentifier("settings-clear-temp")
            if hasActiveHLSJob {
                Text(L("An HLS download is running — clearing now would break it. Try again once it finishes.",
                       "有 HLS 下载正在进行，现在清理会中断它。等它完成后再说。"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Language

    private var languageCard: some View {
        card(title: L("LANGUAGE", "语言")) {
            Picker("", selection: Binding(
                get: { language.language },
                set: { language.set($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        card(title: L("ABOUT", "关于")) {
            HStack {
                Text("FluxKit")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Self.appVersion)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(L("Save HLS playlists, direct links, and podcast episodes for offline playback. No account, no analytics.",
                   "保存 HLS 播放列表、直链和播客节目，离线播放。不需要账号，没有分析 SDK。"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private static var freeSpace: Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
