import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library

    @State private var playing: PlaybackRequest?
    @State private var showMissingFile = false
    @State private var pendingDelete: DownloadRecord?
    @State private var search = ""
    @State private var sort: SortOption = .newest
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmBatchDelete = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var isImporting = false

    enum SortOption: String, CaseIterable {
        case newest, oldest, largest, title

        /// The query layer keeps the ordering rules so they can be unit- and performance-tested.
        var librarySort: LibrarySort {
            switch self {
            case .newest: return .newest
            case .oldest: return .oldest
            case .largest: return .largest
            case .title: return .title
            }
        }

        var label: String {
            switch self {
            case .newest: return L("Newest first", "最新优先")
            case .oldest: return L("Oldest first", "最早优先")
            case .largest: return L("Largest first", "最大优先")
            case .title: return L("Title A–Z", "按标题排序")
            }
        }
    }

    private var visibleRecords: [DownloadRecord] {
        LibraryQuery.apply(library.finished, query: search, sort: sort.librarySort)
    }

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
                            title: L("Your library is empty", "片库还是空的"),
                            message: L("Finished downloads show up here, ready to play offline.",
                                       "下载完成的视频会出现在这里，随时离线播放。")
                        )
                        Spacer(minLength: 0)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            searchField
                            summary
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(visibleRecords) { record in
                                    card(record)
                                        .overlay(alignment: .topTrailing) {
                                            if selecting {
                                                Image(systemName: selection.contains(record.id)
                                                      ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 22, weight: .semibold))
                                                    .foregroundStyle(selection.contains(record.id)
                                                                     ? Theme.accent : .white.opacity(0.8))
                                                    .padding(8)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(selection.contains(record.id)
                                                        ? Theme.accent : Color.clear, lineWidth: 2)
                                        )
                                        .accessibilityElement(children: .contain)
                                        .accessibilityAction {
                                            if selecting {
                                                selection.insert(record.id)
                                            } else {
                                                open(record)
                                            }
                                        }
                                        .onTapGesture {
                                            if selecting {
                                                if selection.contains(record.id) {
                                                    selection.remove(record.id)
                                                } else {
                                                    selection.insert(record.id)
                                                }
                                            } else {
                                                open(record)
                                            }
                                        }
                                        .contextMenu {
                                            Button {
                                                open(record)
                                            } label: {
                                                Label(L("Play", "播放"), systemImage: "play.fill")
                                            }
                                            if let url = library.fileURL(for: record) {
                                                ShareLink(item: url) {
                                                    Label(L("Share", "分享"), systemImage: "square.and.arrow.up")
                                                }
                                            }
                                            Button(role: .destructive) {
                                                pendingDelete = record
                                            } label: {
                                                Label(L("Delete", "删除"), systemImage: "trash")
                                            }
                                        }
                                }
                            }

                            SponsorSlot(style: .native)
                            Color.clear.frame(height: 96)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(selecting ? L("\(selection.count) selected", "已选 \(selection.count) 项") : L("Library", "片库"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? L("Cancel", "取消") : L("Select", "选择")) {
                        selecting.toggle()
                        selection.removeAll()
                    }
                    .accessibilityIdentifier("library-select")
                    .disabled(!selecting && library.finished.isEmpty)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(isImporting)
                    .accessibilityIdentifier("library-import")
                    .accessibilityLabel(L("Import from Files", "从文件导入"))

                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sort = option
                            } label: {
                                if sort == option {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("library-sort")
                    .accessibilityLabel(L("Sort", "排序"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting && !selection.isEmpty {
                    Button(role: .destructive) {
                        confirmBatchDelete = true
                    } label: {
                        Label(L("Delete \(selection.count)", "删除 \(selection.count) 项"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                if !search.isEmpty && visibleRecords.isEmpty {
                    Text(L("No matches", "没有匹配的内容"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.movie, .audio, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .alert(L("Import", "导入"), isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button(L("OK", "好"), role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .confirmationDialog(
                L("Delete \(selection.count) downloads?", "删除 \(selection.count) 个下载？"),
                isPresented: $confirmBatchDelete,
                titleVisibility: .visible
            ) {
                Button(L("Delete", "删除"), role: .destructive) {
                    for id in selection { library.remove(id) }
                    selection.removeAll()
                    selecting = false
                }
                Button(L("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(L("The files will be removed from this device.", "文件会从这台设备上删除。"))
            }
        }
        .fullScreenCover(item: $playing) { request in
            PlayerScreen(request: request)
        }
        .alert(L("File missing", "文件不见了"), isPresented: $showMissingFile) {
            Button(L("OK", "好"), role: .cancel) {}
        } message: {
            Text(L("This download is no longer on the device.", "这个下载已经不在设备上了。"))
        }
        .confirmationDialog(
            pendingDelete.map { L("Delete \"\($0.title)\"?", "删除「\($0.title)」？") } ?? L("Delete download?", "删除这个下载？"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Delete", "删除"), role: .destructive) {
                if let record = pendingDelete { library.remove(record.id) }
                pendingDelete = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("The file will be removed from this device.", "文件会从这台设备上删除。"))
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        Task {
            for url in urls {
                do {
                    _ = try await ImportService.importFile(from: url, library: library)
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            isImporting = false
        }
    }

    private func open(_ record: DownloadRecord) {
        guard let url = library.fileURL(for: record) else {
            showMissingFile = true
            return
        }
        playing = PlaybackRequest(record: record, queue: visibleRecords, fileURL: url)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField(L("Search library", "搜索片库"), text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("library-search-field")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatPill(label: "\(library.finished.count)", caption: L("ITEMS", "个文件"))
            StatPill(label: Fmt.bytes(library.totalBytes), caption: L("ON DEVICE", "已存储"))
            Spacer()
        }
    }

    private func card(_ record: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail(record)

            Text(record.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                // Two lines are always reserved, so one- and two-line titles still tile evenly.
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text("\(Fmt.bytes(record.bytesReceived)) · \(Fmt.relative(record.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                if record.isPlayed {
                    Text(L("Played", "已看完"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.success)
                } else if record.playbackProgress > 0.01 {
                    Text(L("Resume", "继续"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 14, alignment: .leading)
        }
    }

    /// A fixed 16:9 box. The box used to be sized by the thumbnail itself, so a portrait video
    /// stretched its card and the two-column grid came out ragged — the artwork is now drawn as an
    /// overlay (which cannot affect layout) and clipped to the box.
    private func thumbnail(_ record: DownloadRecord) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.surfaceRaised)
            .aspectRatio(16 / 9, contentMode: .fit)
            // The artwork is decorative: `scaledToFill` draws outside the 16:9 box, and
            // `clipShape` only clips *drawing* — without `allowsHitTesting(false)` the overflow
            // swallowed taps for whatever sat above the card (the search field).
            .overlay { thumbnailImage(record).allowsHitTesting(false) }
            .overlay(alignment: .bottomTrailing) {
                durationBadge(record).padding(6).allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if record.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .overlay { progressBar(record).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func thumbnailImage(_ record: DownloadRecord) -> some View {
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
    }

    @ViewBuilder
    private func durationBadge(_ record: DownloadRecord) -> some View {
        let duration = Fmt.duration(record.duration)
        if !duration.isEmpty {
            Text(duration)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.6)))
        }
    }

    @ViewBuilder
    private func progressBar(_ record: DownloadRecord) -> some View {
        if record.playbackProgress > 0.01 {
            VStack {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * record.playbackProgress)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
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
