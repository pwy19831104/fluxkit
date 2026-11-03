import SwiftUI

struct DownloadsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var playing: DownloadRecord?

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
                        title: "No downloads yet",
                        message: "Head to the Download tab, paste a video link and tap Download."
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if !library.active.isEmpty {
                                section(title: "IN PROGRESS", records: library.active)
                            }
                            if !library.failed.isEmpty {
                                section(title: "NEEDS ATTENTION", records: library.failed)
                            }
                            if !library.finished.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("COMPLETED")
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
                                                    Label("Play", systemImage: "play.fill")
                                                }
                                                if let url = library.fileURL(for: record) {
                                                    ShareLink(item: url) {
                                                        Label("Share", systemImage: "square.and.arrow.up")
                                                    }
                                                }
                                                Button(role: .destructive) {
                                                    library.remove(record.id)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Color.clear.frame(height: 12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(item: $playing) { record in
            if let url = library.fileURL(for: record) {
                PlayerScreen(record: record, fileURL: url)
            } else {
                EmptyStateView(icon: "exclamationmark.triangle",
                               title: "File missing",
                               message: "This download is no longer on the device.")
            }
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
        guard library.fileURL(for: record) != nil else { return }
        playing = record
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
