import SwiftUI
import UIKit

struct HomeView: View {
    @Binding var pendingLink: String?

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads

    @State private var link = ""
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var preview: ResolvedMedia?
    @State private var hasClipboardLink = false
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
                    clipboardBanner
                    supportedNote
                    if !library.active.isEmpty {
                        activeSection
                    }
                    howItWorks
                    legalNote
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $preview) { media in
            MediaPreviewSheet(media: media)
        }
        .onAppear(perform: detectClipboard)
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
                Text("DownloadKit")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Paste a link. Keep the video — no account, no clutter.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var inputCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Paste a video link", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isFieldFocused)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(submit)
                if !link.isEmpty {
                    Button {
                        link = ""
                        errorMessage = nil
                    } label: {
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
                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(GhostButtonStyle())

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isResolving {
                            ProgressView().tint(.black)
                        }
                        Text(isResolving ? "Checking…" : "Download")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                .disabled(!canSubmit)
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

    @ViewBuilder
    private var clipboardBanner: some View {
        if hasClipboardLink, link.isEmpty {
            Button(action: pasteFromClipboard) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accentSecondary)
                    Text("Link detected in your clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Use it")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accent.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private var supportedNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
                .padding(.top, 2)
            Text("Direct MP4 / MOV links, HLS (.m3u8) streams, and public pages that embed a video.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IN PROGRESS")
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

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW IT WORKS")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                step(number: "1", title: "Copy a video link", detail: "From Safari, Files, or any app.")
                step(number: "2", title: "Tap Download", detail: "DownloadKit inspects the link and finds the media.")
                step(number: "3", title: "Keep it offline", detail: "Play it in the app or save it to Photos.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private var legalNote: some View {
        Text("Only download videos you have permission to save. DownloadKit doesn't bypass DRM or paid access.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func step(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.surfaceRaised))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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

    private func detectClipboard() {
        guard link.isEmpty else { return }
        UIPasteboard.general.detectPatterns(for: [\.probableWebURL]) { result in
            guard case .success(let patterns) = result, !patterns.isEmpty else { return }
            Task { @MainActor in hasClipboardLink = true }
        }
    }

    private func pasteFromClipboard() {
        let value = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        guard let value, !value.isEmpty else { return }
        link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        hasClipboardLink = false
    }

    private func submit() {
        guard canSubmit else { return }
        isFieldFocused = false
        errorMessage = nil
        isResolving = true

        let input = link
        Task {
            do {
                let media = try await LinkResolver().resolve(input: input)
                preview = media
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isResolving = false
        }
    }
}
