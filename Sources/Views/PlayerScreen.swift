import AVKit
import Combine
import SwiftUI

/// One sheet request: the tapped item plus the list it came from (the play queue).
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let record: DownloadRecord
    let queue: [DownloadRecord]
    let fileURL: URL
}

struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [DownloadRecord]
    @State private var index: Int
    @State private var record: DownloadRecord
    @State private var fileURL: URL
    @State private var player: AVPlayer
    @State private var playback = PlaybackSession()
    @State private var alertMessage: String?
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var speed: Double = 1
    @State private var hasVideoTrack: Bool

    @StateObject private var pip = PiPManager()
    @State private var externalSubtitles: [ExternalSubtitle] = []
    @State private var selectedExternalID: String?
    @State private var currentSubtitleText: String?
    @State private var legibleGroup: AVMediaSelectionGroup?
    @State private var legibleChoices: [LegibleChoice] = []
    @State private var selectedLegibleID: String?

    private let positionTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private let subtitleTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private struct LegibleChoice: Identifiable {
        let id: String
        let option: AVMediaSelectionOption

        var label: String { option.displayName }
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "ogg", "opus", "flac",
    ]

    init(request: PlaybackRequest) {
        let items = request.queue.isEmpty ? [request.record] : request.queue
        let start = items.firstIndex(where: { $0.id == request.record.id }) ?? 0
        _queue = State(initialValue: items)
        _index = State(initialValue: start)
        _record = State(initialValue: request.record)
        _fileURL = State(initialValue: request.fileURL)
        _player = State(initialValue: AVPlayer(url: request.fileURL))
        _hasVideoTrack = State(
            initialValue: !Self.audioExtensions.contains(request.fileURL.pathExtension.lowercased())
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            if !hasVideoTrack {
                audioArtwork
                    .allowsHitTesting(false)
            }

            if let currentSubtitleText {
                subtitleOverlay(currentSubtitleText)
            }

            // 1×1 host used only as the Picture in Picture source.
            PlayerLayerView(player: player) { layer in
                pip.attach(layer: layer)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack {
                topBar
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
        .onAppear(perform: startPlayback)
        .onDisappear(perform: stopPlayback)
        .onReceive(positionTimer) { _ in savePosition() }
        .onReceive(subtitleTimer) { _ in updateSubtitleText() }
        .alert("FluxKit", isPresented: Binding(get: { alertMessage != nil },
                                                  set: { if !$0 { alertMessage = nil } })) {
            Button(L("OK", "好"), role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            L("Delete this download?", "删除这个下载？"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L("Delete", "删除"), role: .destructive) { deleteCurrent() }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("The file will be removed from this device.", "文件会从这台设备上删除。"))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
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
            .accessibilityLabel(L("Close", "关闭"))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if queue.count > 1 {
                queueButton(systemName: "backward.end.fill", enabled: index > 0,
                            label: L("Previous", "上一个")) {
                    switchTo(index - 1)
                }
                queueButton(systemName: "forward.end.fill", enabled: index + 1 < queue.count,
                            label: L("Next", "下一个")) {
                    switchTo(index + 1)
                }
            }

            if !legibleChoices.isEmpty || !externalSubtitles.isEmpty {
                subtitleMenu
            }

            if hasVideoTrack && pip.isSupported {
                Button {
                    pip.toggle()
                } label: {
                    Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .accessibilityLabel(L("Picture in Picture", "画中画"))
            }

            Menu {
                Menu(L("Speed", "速度")) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            speed = rate
                            playback.setRate(rate)
                            settings.playbackSpeed = rate
                        } label: {
                            if abs(speed - rate) < 0.001 {
                                Label(speedLabel(rate), systemImage: "checkmark")
                            } else {
                                Text(speedLabel(rate))
                            }
                        }
                    }
                }
                ShareLink(item: fileURL) {
                    Label(L("Share", "分享"), systemImage: "square.and.arrow.up")
                }
                if hasVideoTrack {
                    Button {
                        saveToPhotos()
                    } label: {
                        Label(L("Save to Photos", "存入相册"), systemImage: "photo.badge.arrow.down")
                    }
                    .disabled(isSaving)
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(L("Delete", "删除"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .accessibilityLabel(L("More", "更多"))
        }
    }

    private func queueButton(
        systemName: String,
        enabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.3))
                .frame(width: 34, height: 38)
                .background(Circle().fill(.black.opacity(enabled ? 0.45 : 0.25)))
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let position = queuePosition {
            parts.append(position)
        }
        parts.append("\(Fmt.bytes(record.bytesReceived)) · \(pathExtensionLabel)")
        return parts.joined(separator: " · ")
    }

    private var queuePosition: String? {
        guard queue.count > 1 else { return nil }
        return L("\(index + 1) of \(queue.count)", "\(index + 1) / \(queue.count)")
    }

    // MARK: - Subtitles

    private var subtitleMenu: some View {
        Menu {
            Button {
                deselectSubtitles()
            } label: {
                if selectedExternalID == nil && selectedLegibleID == nil {
                    Label(L("Off", "关闭"), systemImage: "checkmark")
                } else {
                    Text(L("Off", "关闭"))
                }
            }

            if !legibleChoices.isEmpty {
                Section(L("In this file", "文件内")) {
                    ForEach(legibleChoices) { choice in
                        Button {
                            selectLegible(choice)
                        } label: {
                            if selectedLegibleID == choice.id {
                                Label(choice.label, systemImage: "checkmark")
                            } else {
                                Text(choice.label)
                            }
                        }
                    }
                }
            }

            if !externalSubtitles.isEmpty {
                Section(L("Downloaded", "已下载")) {
                    ForEach(externalSubtitles) { track in
                        Button {
                            selectExternal(track)
                        } label: {
                            if selectedExternalID == track.id {
                                Label(track.label, systemImage: "checkmark")
                            } else {
                                Text(track.label)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedExternalID != nil || selectedLegibleID != nil
                  ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .accessibilityLabel(L("Subtitles", "字幕"))
    }

    private func subtitleOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.6))
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 90)
        }
        .allowsHitTesting(false)
    }

    private func loadSubtitleOptions(for record: DownloadRecord, fileURL: URL) {
        externalSubtitles = AppPaths.subtitleFiles(recordID: record.id).map { url in
            let code = url.deletingPathExtension().lastPathComponent
                .split(separator: ".").last.map(String.init) ?? "und"
            let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
            return ExternalSubtitle(languageCode: code, label: name.capitalized, url: url)
        }
        selectedExternalID = nil
        selectedLegibleID = nil
        currentSubtitleText = nil
        legibleGroup = nil
        legibleChoices = []

        Task {
            let asset = AVURLAsset(url: fileURL)
            guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else { return }
            legibleGroup = group
            legibleChoices = group.options.enumerated().map { offset, option in
                LegibleChoice(id: "\(offset)-\(option.displayName)", option: option)
            }
        }
    }

    private func deselectSubtitles() {
        selectedExternalID = nil
        selectedLegibleID = nil
        currentSubtitleText = nil
        if let group = legibleGroup, let item = player.currentItem {
            item.select(nil, in: group)
        }
    }

    private func selectLegible(_ choice: LegibleChoice) {
        selectedExternalID = nil
        currentSubtitleText = nil
        selectedLegibleID = choice.id
        if let group = legibleGroup, let item = player.currentItem {
            item.select(choice.option, in: group)
        }
    }

    private func selectExternal(_ track: ExternalSubtitle) {
        selectedLegibleID = nil
        if let group = legibleGroup, let item = player.currentItem {
            item.select(nil, in: group)
        }
        loadCuesIfNeeded(track.id)
        selectedExternalID = track.id
        updateSubtitleText()
    }

    private func loadCuesIfNeeded(_ id: String) {
        guard let index = externalSubtitles.firstIndex(where: { $0.id == id }),
              externalSubtitles[index].cues.isEmpty else { return }
        guard let text = try? String(contentsOf: externalSubtitles[index].url, encoding: .utf8) else { return }
        externalSubtitles[index].cues = WebVTTParser.parse(text)
    }

    private func updateSubtitleText() {
        guard let id = selectedExternalID,
              let track = externalSubtitles.first(where: { $0.id == id }) else {
            if currentSubtitleText != nil { currentSubtitleText = nil }
            return
        }
        let time = playback.currentPosition
        let text = track.cues.first { time >= $0.start && time <= $0.end }?.text
        if text != currentSubtitleText {
            currentSubtitleText = text
        }
    }

    // MARK: - Audio card

    private var audioArtwork: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.brandGradient.opacity(0.35))
                .frame(width: 190, height: 190)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                )

            Text(record.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(L("Audio · saved offline", "音频 · 已离线保存"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(28)
        .frame(maxWidth: 360)
    }

    // MARK: - Playback lifecycle

    private func startPlayback() {
        speed = settings.playbackSpeed
        pip.onStop = { [weak player] in player?.play() }
        pip.onFailure = { message in alertMessage = message }
        loadSubtitleOptions(for: record, fileURL: fileURL)
        let startAt = library.record(id: record.id)?.lastPosition ?? record.lastPosition
        playback.onEnded = { handleEnded() }
        playback.activate(
            player: player,
            title: record.title,
            artworkURL: library.thumbnailURL(for: record) ?? record.thumbnailRemoteURL,
            startAt: startAt,
            rate: speed
        )
        loadTrackInfo(for: fileURL)
    }

    private func loadTrackInfo(for url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            hasVideoTrack = !tracks.isEmpty
        }
    }

    private func stopPlayback() {
        savePosition()
        settings.playbackSpeed = speed
        playback.onEnded = nil
        playback.deactivate()
        pip.stop()
    }

    private func handleEnded() {
        library.update(record.id) { item in
            item.played = true
            item.lastPosition = nil
        }
        let next = index + 1
        if queue.indices.contains(next), library.fileURL(for: queue[next]) != nil {
            switchTo(next)
        }
    }

    private func switchTo(_ newIndex: Int) {
        guard queue.indices.contains(newIndex), newIndex != index else { return }
        savePosition()
        let next = queue[newIndex]
        guard let url = library.fileURL(for: next) else {
            alertMessage = L("This file is no longer on the device.",
                             "这个文件已经不在设备上了。")
            return
        }
        playback.deactivate()
        index = newIndex
        record = next
        fileURL = url
        player = AVPlayer(url: url)
        hasVideoTrack = !Self.audioExtensions.contains(url.pathExtension.lowercased())
        startPlayback()
    }

    private func deleteCurrent() {
        player.pause()
        playback.deactivate()
        library.remove(record.id)
        queue.removeAll { $0.id == record.id }
        guard !queue.isEmpty else {
            dismiss()
            return
        }
        index = min(index, queue.count - 1)
        let next = queue[index]
        guard let url = library.fileURL(for: next) else {
            dismiss()
            return
        }
        record = next
        fileURL = url
        player = AVPlayer(url: url)
        hasVideoTrack = !Self.audioExtensions.contains(url.pathExtension.lowercased())
        startPlayback()
    }

    private func savePosition() {
        let position = playback.currentPosition
        let duration = playback.currentDuration
        guard position > 1 else { return }
        let finished = duration > 0 && position >= duration - 5
        library.update(record.id) { item in
            if finished {
                item.played = true
                item.lastPosition = nil
            } else {
                item.played = false
                item.lastPosition = position
            }
        }
    }

    private func speedLabel(_ rate: Double) -> String {
        switch rate {
        case 0.75: return "0.75×"
        case 1: return "1×"
        case 1.25: return "1.25×"
        case 1.5: return "1.5×"
        case 2: return "2×"
        default: return String(format: "%.2f×", rate)
        }
    }

    private var pathExtensionLabel: String {
        let ext = fileURL.pathExtension
        return ext.isEmpty ? L("VIDEO", "视频") : ext.uppercased()
    }

    private func saveToPhotos() {
        guard !isSaving else { return }
        guard fileURL.pathExtension.lowercased() != "ts" else {
            alertMessage = L("This video can't be saved to Photos. Use Share to send it to another app instead.",
                             "这个视频无法存入相册，请用分享发送到其它 App。")
            return
        }
        isSaving = true
        Task {
            do {
                try await PhotoSaver.saveVideo(at: fileURL)
                alertMessage = L("Saved to your photo library.", "已保存到相册。")
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
