import SwiftUI

struct PodcastsView: View {
    @Environment(PodcastStore.self) private var store

    @State private var selected: PodcastFeed?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.feeds.isEmpty {
                    EmptyStateView(
                        icon: "dot.radiowaves.left.and.right",
                        title: L("No podcasts yet", "还没有播客订阅"),
                        message: L("Add a podcast RSS feed, or paste one on the Download tab.",
                                   "添加播客订阅地址，或在「下载」页粘贴。")
                    )
                } else {
                    list
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("Podcasts", "播客"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L("Add podcast", "添加播客"))
                }
            }
            .refreshable { await store.refreshAll() }
            .sheet(isPresented: $showAdd) {
                AddPodcastSheet()
            }
            .sheet(item: $selected) { feed in
                PodcastFeedSheet(feed: store.feed(withURL: feed.feedURL) ?? feed)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.sortedFeeds) { feed in
                Button {
                    selected = feed
                } label: {
                    PodcastRow(feed: feed)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.unsubscribe(feed.feedURL)
                    } label: {
                        Label(L("Remove", "移除"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .top) {
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }
}

private struct PodcastRow: View {
    let feed: PodcastFeed

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let author = feed.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private var subtitle: String {
        let count = feed.episodes.count
        let date = feed.episodes.first?.publishedAt
            .map { $0.formatted(.dateTime.year().month(.abbreviated).day()) }
        let episodes = L("\(count) episodes", "\(count) 期")
        return [date, episodes].compactMap { $0 }.joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised)
            if let url = feed.artworkURL {
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
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AddPodcastSheet: View {
    @Environment(PodcastStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isAdding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(L("https://example.com/feed.xml", "https://example.com/feed.xml"), text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.stroke, lineWidth: 1)
                            )
                    )

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                }

                Button {
                    add()
                } label: {
                    HStack {
                        if isAdding { ProgressView().tint(.black) }
                        Text(isAdding ? L("Checking…", "检查中…") : L("Add podcast", "添加播客"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                .disabled(!canSubmit)

                Text(L("Paste the show's RSS/Atom feed URL — often linked as “RSS” on the show's site.",
                       "粘贴节目的 RSS / Atom 订阅地址——通常在节目官网的「RSS」链接里。"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("Add podcast", "添加播客"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "取消")) { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAdding
    }

    private func add() {
        guard canSubmit else { return }
        isAdding = true
        error = nil
        let input = text
        Task {
            do {
                _ = try await store.addFeed(from: input)
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isAdding = false
        }
    }
}
