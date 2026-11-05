import SwiftUI

/// Episode picker for a pasted podcast/RSS feed.
struct PodcastFeedSheet: View {
    let feed: PodcastFeed

    @Environment(DownloadManager.self) private var downloads
    @Environment(LibraryStore.self) private var library
    @Environment(PodcastStore.self) private var podcasts
    @Environment(\.dismiss) private var dismiss

    @State private var added: Set<String> = []
    @State private var errorMessage: String?

    private var isSubscribed: Bool {
        podcasts.isSubscribed(feed.feedURL)
    }

    private func toggleSubscription() {
        if isSubscribed {
            podcasts.unsubscribe(feed.feedURL)
        } else {
            podcasts.subscribe(feed)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let newest = feed.episodes.first {
                        Button {
                            add(newest)
                        } label: {
                            Label(
                                added.contains(newest.id) || isDownloaded(newest)
                                    ? L("Newest episode added", "已添加最新一期")
                                    : L("Download newest episode", "下载最新一期"),
                                systemImage: "arrow.down.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(added.contains(newest.id) || isDownloaded(newest))
                        .opacity(added.contains(newest.id) || isDownloaded(newest) ? 0.6 : 1)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }

                    Text(L("\(feed.episodes.count) EPISODES", "\(feed.episodes.count) 期节目"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)

                    LazyVStack(spacing: 10) {
                        ForEach(feed.episodes) { episode in
                            row(episode)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("Podcast", "播客"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close", "关闭")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleSubscription()
                    } label: {
                        Text(isSubscribed ? L("Subscribed", "已订阅") : L("Subscribe", "订阅"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(isSubscribed ? Theme.success : Theme.accent)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(feed.artworkURL, size: 86)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                if let author = feed.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Text(Fmt.host(feed.feedURL))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private func artwork(_ url: URL?, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceRaised)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "waveform")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Episode row

    private func row(_ episode: PodcastEpisode) -> some View {
        let downloaded = added.contains(episode.id) || isDownloaded(episode)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(meta(episode))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                add(episode)
            } label: {
                Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(downloaded ? Theme.success : Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(downloaded)
            .accessibilityLabel(
                downloaded
                    ? L("Added to downloads", "已加入下载")
                    : L("Download \(episode.title)", "下载 \(episode.title)")
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private func meta(_ episode: PodcastEpisode) -> String {
        var parts: [String] = []
        if let date = episode.publishedAt {
            parts.append(date.formatted(.dateTime.year().month(.abbreviated).day()))
        }
        let duration = Fmt.duration(episode.duration)
        if !duration.isEmpty {
            parts.append(duration)
        }
        if let bytes = episode.byteLength, bytes > 0 {
            parts.append(Fmt.bytes(bytes))
        }
        if let record = library.records.first(where: { $0.remoteURL == episode.enclosureURL }) {
            if record.isPlayed {
                parts.append(L("Played", "已听完"))
            } else if record.playbackProgress > 0.01 {
                parts.append(L("Resume", "继续"))
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func isDownloaded(_ episode: PodcastEpisode) -> Bool {
        library.records.contains { $0.remoteURL == episode.enclosureURL }
    }

    private func add(_ episode: PodcastEpisode) {
        guard !isDownloaded(episode), !added.contains(episode.id) else { return }
        downloads.start(episode.media(feed: feed))
        withAnimation(.easeOut(duration: 0.15)) {
            _ = added.insert(episode.id)
        }
        errorMessage = nil
    }
}

#Preview {
    PodcastFeedSheet(
        feed: PodcastFeed(
            title: "The Example Show",
            author: "Example Media",
            artworkURL: nil,
            feedURL: URL(string: "https://example.com/feed.xml")!,
            episodes: [
                PodcastEpisode(
                    title: "Episode 12 — HLS without the headache",
                    publishedAt: Date(),
                    duration: 1830,
                    byteLength: 42_000_000,
                    enclosureURL: URL(string: "https://example.com/12.mp3")!,
                    mimeType: "audio/mpeg",
                    artworkURL: nil
                ),
                PodcastEpisode(
                    title: "Episode 11 — Direct links",
                    publishedAt: Date().addingTimeInterval(-86_400 * 7),
                    duration: 1500,
                    byteLength: 36_000_000,
                    enclosureURL: URL(string: "https://example.com/11.mp3")!,
                    mimeType: "audio/mpeg",
                    artworkURL: nil
                ),
            ]
        )
    )
    .preferredColorScheme(.dark)
}
