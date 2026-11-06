import SwiftUI

struct DownloadsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var playing: PlaybackRequest?
    /// Deleting here removes the file itself, so it asks first — same rule as the library tab.
    @State private var pendingDelete: DownloadRecord?

    private var isEmpty: Bool {
        library.active.isEmpty && library.failed.isEmpty && library.finished.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if isEmpty {
                    EmptyStateView(
                        icon: "arrow.down.circle",
                        title: L("No downloads yet", "还没有下载任务"),
                        message: L("Paste a link or podcast feed on the Download tab to get started.",
                                   "去「下载」页粘贴链接或播客订阅就能开始。")
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if !library.active.isEmpty {
                                section(title: L("IN PROGRESS", "进行中"), records: library.active)
                            }
                            if !library.failed.isEmpty {
                                section(title: L("NEEDS ATTENTION", "需要处理"), records: library.failed)
                            }
                            if !library.finished.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(L("COMPLETED", "已完成"))
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.textSecondary)
                                    VStack(spacing: 10) {
                                        ForEach(library.finished) { record in
                                            DownloadRow(record: record) {
                                                open(record)
                                            }
                                            .contextMenu {
                                                Button {
                                                    open(record)
                                                } label: {
                                                    Label(L("Play", "播放"), systemImage: "play.fill")
                                                }
                                                if let url = library.fileURL(for: record) {
                                                    ShareLink(item: url) {
                                                        Label(L("Share", "分享"), systemImage: "square.and.arrow.up")
                                                    }
                                                }
                                                Button(role: .destructive) {
                                                    pendingDelete = record
                                                } label: {
                                                    Label(L("Delete", "删除"), systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SponsorSlot(style: .banner)
                            Color.clear.frame(height: 96)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(L("Downloads", "下载任务"))
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(item: $playing) { request in
            PlayerScreen(request: request)
        }
        .confirmationDialog(
            L("Delete this download?", "删除这个下载？"),
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Delete", "删除"), role: .destructive) {
                if let record = pendingDelete { library.remove(record.id) }
                pendingDelete = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("The file will be removed from this device.", "文件会从这台设备上删除。"))
        }
    }

    private func section(title: String, records: [DownloadRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 10) {
                ForEach(records) { record in
                    DownloadRow(record: record)
                }
            }
        }
    }

    private func open(_ record: DownloadRecord) {
        guard let url = library.fileURL(for: record) else { return }
        playing = PlaybackRequest(record: record, queue: library.finished, fileURL: url)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
