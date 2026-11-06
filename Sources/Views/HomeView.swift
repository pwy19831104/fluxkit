import SwiftUI
import UIKit

struct HomeView: View {
    @Binding var pendingLink: String?

    @Environment(LibraryStore.self) private var library
    @Environment(LanguageStore.self) private var language

    @State private var link = ""
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var preview: ResolvedMedia?
    @State private var podcast: PodcastFeed?
    @FocusState private var isFieldFocused: Bool

    private var canSubmit: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResolving
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    inputCard
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    quickTip
                    if !library.active.isEmpty {
                        activeSection
                    }
                    SponsorSlot(style: .banner)
                    legalNote
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $preview) { media in
            MediaPreviewSheet(media: media)
        }
        .sheet(item: $podcast) { feed in
            PodcastFeedSheet(feed: feed)
        }
        .onChange(of: pendingLink) { _, newValue in
            guard let newValue else { return }
            link = newValue
            pendingLink = nil
            submit()
        }
        #if DEBUG
        .onAppear(perform: debugAutofill)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
                Text("FluxKit")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("home-title")
                Spacer(minLength: 8)
                languageMenu
            }
            Text(L("Save HLS video, direct links, and podcasts.",
                   "保存 HLS 视频、直链和播客。"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// English / 中文. Written in each language so both are readable; the default comes from the
    /// device region until the user picks one here.
    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases, id: \.self) { option in
                Button {
                    language.set(option)
                } label: {
                    if language.language == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
        }
        .accessibilityLabel(L("Language", "语言"))
    }

    private var inputCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(Theme.textSecondary)
                TextField(L("Paste a link or podcast feed", "粘贴链接或播客订阅"), text: $link)
                    .accessibilityIdentifier("home-link-field")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isFieldFocused)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(submit)
                if !link.isEmpty {
                    Button(action: clearInput) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.background.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isFieldFocused ? Theme.accent.opacity(0.8) : Theme.stroke, lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                // A `PasteButton` would skip iOS's "Allow Paste?" prompt, but it renders the
                // system's own label in the *system* language, which fights this app's in-app
                // language switch. So the label stays ours and the read is explicit.
                Button(action: pasteFromClipboard) {
                    Label(L("Paste", "粘贴"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(GhostButtonStyle())
                .accessibilityIdentifier("home-paste")

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isResolving {
                            ProgressView().tint(.black)
                        }
                        Text(isResolving ? L("Checking…", "解析中…") : L("Download", "下载"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                .disabled(!canSubmit)
                .accessibilityIdentifier("home-download")
            }
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

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.danger.opacity(0.12))
        )
    }

    private var quickTip: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            Text(L("Copy a link, then tap Paste — HLS playlists, media files, or a podcast feed.",
                   "复制链接后点「粘贴」——HLS 播放列表、音视频文件或播客订阅。"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("IN PROGRESS", "进行中"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                ForEach(library.active) { record in
                    DownloadRow(record: record, compact: true)
                }
            }
        }
    }

    private var legalNote: some View {
        Text(L("Only download media you have the right to save.",
               "请只下载你有权保存的媒体。"))
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    // MARK: - Actions

    #if DEBUG
    private func debugAutofill() {
        guard let value = ProcessInfo.processInfo.environment["PREVIEW_URL"],
              link.isEmpty, !isResolving else { return }
        link = value
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            submit()
        }
    }
    #endif

    private func clearInput() {
        link = ""
        errorMessage = nil
    }

    private func pasteFromClipboard() {
        // `string` first: share blurbs (“复制打开抖音… https://…”) arrive as plain text, not URL items.
        let raw = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
        guard let raw, !raw.isEmpty else {
            errorMessage = L("Clipboard is empty, or iOS didn't allow reading it.",
                             "剪贴板是空的，或者系统没有允许读取剪贴板。")
            return
        }
        acceptPasted(raw)
    }

    /// Share blurbs arrive as plain text, so the link is extracted before it lands in the field.
    private func acceptPasted(_ pasted: String) {
        guard let extracted = LinkResolver.linkString(in: pasted) else {
            errorMessage = L("No link found in what you pasted.", "粘贴的内容里没有找到链接。")
            return
        }
        link = extracted
        errorMessage = nil
    }

    private func submit() {
        guard canSubmit else { return }
        // Accept whole share blobs: keep only the link part before resolving.
        if let extracted = LinkResolver.linkString(in: link) {
            link = extracted
        }
        isFieldFocused = false
        errorMessage = nil
        isResolving = true

        let input = link
        Task {
            do {
                switch try await LinkResolver().resolveInput(input) {
                case .media(let media):
                    preview = media
                case .podcast(let feed):
                    podcast = feed
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isResolving = false
        }
    }
}
