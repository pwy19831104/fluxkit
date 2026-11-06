import SwiftUI

struct MediaPreviewSheet: View {
    let media: ResolvedMedia

    @Environment(DownloadManager.self) private var downloads
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

    /// Same address already in the list (queued, downloading or finished on disk).
    private var existing: DownloadRecord? {
        library.records.first { record in
            guard record.remoteURL == media.url || record.sourceURL == media.url else { return false }
            return record.isActive || library.fileURL(for: record) != nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        thumbnail
                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayTitle)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(3)
                            Text(Fmt.host(media.pageURL ?? media.url))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        infoGrid

                        HStack(spacing: 10) {
                            Button {
                                guard !started else { return }
                                downloads.start(media)
                                started = true
                                dismiss()
                            } label: {
                                Label(existing == nil
                                      ? L("Start download", "开始下载")
                                      : L("Already in Downloads", "已在下载列表里"),
                                      systemImage: existing == nil
                                      ? "arrow.down.to.line.compact"
                                      : "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle(enabled: existing == nil))
                            .disabled(existing != nil)
                        }

                        Text(L("Saved in the app. Share it or save it to Photos when it's done.",
                               "保存在 App 里，完成后可分享或存入相册。"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("Ready to download", "准备下载"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close", "关闭")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    private var displayTitle: String {
        if let title = media.title, !title.isEmpty { return title }
        let name = media.url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? L("Video", "视频") : name
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
            if let url = media.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 46, weight: .regular))
            .foregroundStyle(Theme.textSecondary.opacity(0.5))
    }

    private var infoGrid: some View {
        HStack(spacing: 10) {
            infoCell(title: L("SIZE", "大小"), value: Fmt.bytes(media.contentLength ?? 0))
            infoCell(title: L("FORMAT", "格式"), value: media.fileExtension.uppercased())
        }
    }

    private func infoCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
    }
}
