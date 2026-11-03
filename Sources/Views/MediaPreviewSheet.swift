import SwiftUI

struct MediaPreviewSheet: View {
    let media: ResolvedMedia

    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

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
                                Label("Start download", systemImage: "arrow.down.to.line.compact")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }

                        Text("Saved inside the app. Share it or save it to Photos when it's done.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ready to download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
        return name.isEmpty ? "Video" : name
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
            infoCell(title: "TYPE", value: media.kind == .hls ? "HLS stream" : "Video file")
            infoCell(title: "SIZE", value: Fmt.bytes(media.contentLength ?? 0))
            infoCell(title: "FORMAT", value: media.fileExtension.uppercased())
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
