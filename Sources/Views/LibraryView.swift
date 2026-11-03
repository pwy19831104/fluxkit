import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library

    @State private var playing: DownloadRecord?
    @State private var pendingDelete: DownloadRecord?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if library.finished.isEmpty {
                    VStack(spacing: 18) {
                        EmptyStateView(
                            icon: "play.rectangle.on.rectangle",
                            title: "Your library is empty",
                            message: "Finished downloads show up here, ready to play offline."
                        )
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            summary
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(library.finished) { record in
                                    card(record)
                                        .onTapGesture { playing = record }
                                        .contextMenu {
                                            Button {
                                                playing = record
                                            } label: {
                                                Label("Play", systemImage: "play.fill")
                                            }
                                            if let url = library.fileURL(for: record) {
                                                ShareLink(item: url) {
                                                    Label("Share", systemImage: "square.and.arrow.up")
                                                }
                                            }
                                            Button(role: .destructive) {
                                                pendingDelete = record
                                            } label: {
                                                Label("Delete", systemImage: "trash")
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
            .navigationTitle("Library")
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
        .confirmationDialog(
            pendingDelete.map { "Delete \"\($0.title)\"?" } ?? "Delete download?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let record = pendingDelete { library.remove(record.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The file will be removed from this device.")
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatPill(label: "\(library.finished.count)", caption: "VIDEOS")
            StatPill(label: Fmt.bytes(library.totalBytes), caption: "ON DEVICE")
            Spacer()
        }
    }

    private func card(_ record: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surfaceRaised)
                if let url = library.thumbnailURL(for: record),
                   let image = ThumbnailCache.shared.image(for: url) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if !Fmt.duration(record.duration).isEmpty {
                            Text(Fmt.duration(record.duration))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.6)))
                        }
                    }
                }
                .padding(6)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(record.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(Fmt.bytes(record.bytesReceived)) · \(Fmt.relative(record.createdAt))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct StatPill: View {
    let label: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(caption)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }
}
