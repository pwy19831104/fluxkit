import AVKit
import SwiftUI

struct PlayerScreen: View {
    let record: DownloadRecord
    let fileURL: URL

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var alertMessage: String?
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    init(record: DownloadRecord, fileURL: URL) {
        self.record = record
        self.fileURL = fileURL
        _player = State(initialValue: AVPlayer(url: fileURL))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            VStack {
                topBar
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
        .alert("DownloadKit", isPresented: Binding(get: { alertMessage != nil },
                                                  set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Delete this download?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                player.pause()
                library.remove(record.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be removed from this device.")
        }
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    player.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.45)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(Fmt.bytes(record.bytesReceived)) · \(pathExtensionLabel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 0)

                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.45)))
                }

                Button {
                    saveToPhotos()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.45)))
                }
                .disabled(isSaving)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
            }
        }
    }

    private var pathExtensionLabel: String {
        let ext = fileURL.pathExtension
        return ext.isEmpty ? "VIDEO" : ext.uppercased()
    }

    private func saveToPhotos() {
        guard !isSaving else { return }
        guard fileURL.pathExtension.lowercased() != "ts" else {
            alertMessage = "This stream was saved as a transport stream, which Photos doesn't accept. Use Share to move it to another app."
            return
        }
        isSaving = true
        Task {
            do {
                try await PhotoSaver.saveVideo(at: fileURL)
                alertMessage = "Saved to your photo library."
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
