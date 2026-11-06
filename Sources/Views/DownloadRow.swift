import SwiftUI
import UIKit

/// Decoded-thumbnail cache so scrolling lists don't hit the disk on every frame.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct ThumbnailView: View {
    let localURL: URL?
    var remoteURL: URL?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surfaceRaised)

            if let localURL, let image = ThumbnailCache.shared.image(for: localURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        Image(systemName: "film")
            .font(.system(size: size * 0.34, weight: .medium))
            .foregroundStyle(Theme.textSecondary.opacity(0.7))
    }
}

struct DownloadRow: View {
    let record: DownloadRecord
    var compact: Bool = false
    var onTap: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 12) {
                ThumbnailView(localURL: library.thumbnailURL(for: record),
                              remoteURL: nil,
                              size: compact ? 38 : 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(compact ? 1 : 2)
                    HStack(spacing: 5) {
                        if record.state == .running {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 5, height: 5)
                        }
                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
                trailingControl
            }

            if record.state == .running || record.state == .queued || record.state == .paused {
                ProgressView(value: max(record.progress, 0.02))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }
        }
        .padding(compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onTap?() }
        // `onTapGesture` on a container is invisible to VoiceOver; expose it as an action too.
        .accessibilityElement(children: .contain)
        .accessibilityAction { onTap?() }
    }

    private var statusText: String {
        switch record.state {
        case .queued:
            return record.errorMessage ?? L("Waiting to start", "等待开始")
        case .running:
            // HLS totals are estimates: when one is missing or already exceeded, a percentage
            // would read "100% · 10.8 MB / 0 MB", so show plain progress instead.
            if record.bytesExpected > record.bytesReceived {
                return L("\(Int(record.progress * 100))% · \(Fmt.bytes(record.bytesReceived)) of \(Fmt.bytes(record.bytesExpected))",
                         "\(Int(record.progress * 100))% · \(Fmt.bytes(record.bytesReceived)) / \(Fmt.bytes(record.bytesExpected))")
            }
            return L("Downloading · \(Fmt.bytes(record.bytesReceived))", "下载中 · \(Fmt.bytes(record.bytesReceived))")
        case .paused:
            return record.bytesReceived > 0
                ? L("Paused · \(Fmt.bytes(record.bytesReceived))", "已暂停 · \(Fmt.bytes(record.bytesReceived))")
                : L("Paused", "已暂停")
        case .finished:
            let duration = Fmt.duration(record.duration)
            let base = duration.isEmpty
                ? "\(Fmt.bytes(record.bytesReceived)) · \(Fmt.relative(record.createdAt))"
                : "\(Fmt.bytes(record.bytesReceived)) · \(duration)"
            if record.isPlayed { return base + " · " + L("Played", "已看完") }
            if record.playbackProgress > 0.01 { return base + " · " + L("Resume", "继续") }
            return base
        case .failed:
            return record.errorMessage ?? L("Failed", "失败")
        case .cancelled:
            return L("Cancelled", "已取消")
        }
    }

    private var statusColor: Color {
        switch record.state {
        case .failed:
            return Theme.danger
        case .finished:
            return Theme.success
        default:
            return Theme.textSecondary
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch record.state {
        case .running, .queued:
            HStack(spacing: 12) {
                // HLS jobs can pause too (their segments stay on disk), so the control is no
                // longer limited to progressive transfers.
                if record.state == .running {
                    Button {
                        downloads.pause(record.id)
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Pause", "暂停"))
                }
                Button {
                    downloads.cancel(record.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Cancel", "取消"))
            }
        case .paused:
            Button {
                downloads.resume(record)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Resume", "继续"))
        case .failed, .cancelled:
            if record.isImported == true {
                // Nothing to retry: the file came from Files.app, not from a URL.
                Image(systemName: "doc.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .accessibilityLabel(L("Imported file", "导入的文件"))
            } else {
                Button {
                    downloads.retry(record)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Retry", "重试"))
            }
        case .finished:
            Image(systemName: "play.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.success)
        }
    }
}
