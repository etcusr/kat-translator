import SwiftUI
import OfflineCore
struct HistoryView: View {
    @ObservedObject var history: HistoryModel
    @Environment(\.dismiss) private var dismiss
    @State private var share: SharedAudio?
    @State private var openedImage: (id: UUID, url: URL)?
    @State private var deleting: HistoryEntry?
    @State private var expanded = Set<UUID>()
    var body: some View {
        NavigationStack {
            List {
                if let error = history.error { Text(error).foregroundStyle(.orange) }
                if history.entries.isEmpty {
                    ContentUnavailableView(L10n.text("История пока пуста"), systemImage: "clock", description: Text(L10n.text("Сохранение текста, аудио и изображений можно включить в настройках.")))
                }
                ForEach(history.entries) { entry in
                    #if os(macOS)
                    Section { desktopEntry(entry) }
                    #else
                    Section {
                        HStack {
                            Text(entryTitle(entry)).font(.subheadline.weight(.semibold))
                            Spacer(); Text(entry.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        if entry.hasImage { imageActions(entry) }
                        if let text = entry.text {
                            Text(text.original).foregroundStyle(entry.isOriginalAudio ? .primary : .secondary).textSelection(.enabled)
                            if !entry.isOriginalAudio {
                                Text(text.translation).textSelection(.enabled)
                                CopyTextButton(text: text.translation, title: L10n.text("Скопировать перевод"), showsTitle: true)
                            }
                            CopyTextButton(text: text.original, title: L10n.text("Скопировать оригинал"), showsTitle: true)
                        } else { Text(L10n.text("Текст не сохранён или удалён по настройкам хранения")).font(.caption).foregroundStyle(.secondary) }
                        if entry.hasAudio {
                            PlaybackControls(active: history.playingID == entry.id, paused: history.isPaused,
                                disabled: false, speed: history.playbackSpeed, startLabel: L10n.text("Послушать"),
                                identifier: "history.playback." + entry.id.uuidString,
                                start: { Task { await history.play(entry) } }, stop: history.stopPlayback,
                                pauseResume: history.togglePause, selectSpeed: history.setPlaybackSpeed)
                                .buttonStyle(.borderless)
                            Button { Task { if let url = await history.shareURL(entry.id) { share = SharedAudio(url: url) } } } label: {
                                Label(entry.kind == .originalRecording ? L10n.text("Поделиться записью оригинала") : L10n.text("Поделиться озвучкой"), systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(L10n.text("Удалить запись"), role: .destructive) { deleting = entry }
                    }
                    #endif
                }
            }.katScreenSurface().katPanelTypography().navigationTitle(L10n.text("История переводов"))
                .katDoneToolbar { dismiss() }
                .task { await history.refresh() }
                .onDisappear { history.stopPlayback() }
                .sheet(item: Binding(get: { share }, set: { value in if let value { share = value } else { clearShare() } })) { item in AudioShareSheet(item: item, done: clearShare) }
                .confirmationDialog(L10n.text("Удалить эту запись и сохранённые файлы?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button(L10n.text("Удалить"), role: .destructive) { if let entry = deleting { Task { await history.remove(entry) } }; deleting = nil }
                }
        }.katSheetClose(identifier: "history.close") { dismiss() }
            .katTextReader(isPresented: Binding(get: { openedImage != nil }, set: { if !$0 { closeImage() } })) {
                if let openedImage {
                    HistoryImageReader(url: openedImage.url, close: closeImage)
                }
            }


    }
    #if os(macOS)
    private func desktopEntry(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(entryTitle(entry))
                    .font(AppPlatform.panelHeading)
                Spacer(minLength: 16)
                Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
            }
            if entry.hasImage { imageActions(entry) }
            if let text = entry.text {
                let full = expanded.contains(entry.id)
                if HistoryPreview.isLong(text.original) || HistoryPreview.isLong(text.translation) {
                    Button {
                        if full { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                    } label: {
                        Label(full ? L10n.text("Свернуть") : L10n.text("Показать полностью"), systemImage: full ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("history.expand." + entry.id.uuidString)
                        .accessibilityValue(full ? "expanded" : "collapsed")
                }
                Text(full ? text.original : HistoryPreview.text(text.original))
                    .font(.system(size: 16)).lineSpacing(3)
                    .foregroundStyle(entry.isOriginalAudio ? .primary : .secondary).textSelection(.enabled)
                    .accessibilityIdentifier("history.original." + entry.id.uuidString)
                if !entry.isOriginalAudio {
                Text(full ? text.translation : HistoryPreview.text(text.translation))
                    .font(.system(size: 16)).lineSpacing(3)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("history.translation." + entry.id.uuidString)
                }
            } else {
                Text(L10n.text("Текст не сохранён или удалён по настройкам хранения"))
                    .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        if let text = entry.text { copyButtons(text, translation: !entry.isOriginalAudio) }
                        mediaButtons(entry)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) {
                        if let text = entry.text { HStack(spacing: 12) { copyButtons(text, translation: !entry.isOriginalAudio) } }
                        HStack(spacing: 12) { mediaButtons(entry) }
                    }
                }
                Spacer(minLength: 0)
                deleteButton(entry)
            }.accessibilityIdentifier("history.actions." + entry.id.uuidString)
        }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func mediaButtons(_ entry: HistoryEntry) -> some View {
        if entry.hasAudio {
            PlaybackControls(active: history.playingID == entry.id, paused: history.isPaused,
                disabled: false, speed: history.playbackSpeed, startLabel: L10n.text("Послушать"),
                identifier: "history.playback." + entry.id.uuidString,
                start: { Task { await history.play(entry) } }, stop: history.stopPlayback,
                pauseResume: history.togglePause, selectSpeed: history.setPlaybackSpeed)
                .buttonStyle(.borderless)
            Button { Task { if let url = await history.shareURL(entry.id) { share = SharedAudio(url: url) } } } label: {
                Label(entry.kind == .originalRecording ? L10n.text("Поделиться записью оригинала") : L10n.text("Поделиться озвучкой"), systemImage: "square.and.arrow.up")
            }.accessibilityIdentifier("history.shareAudio." + entry.id.uuidString)
        }
        if entry.hasImage { imageShareButton(entry.id) }
    }
    private func deleteButton(_ entry: HistoryEntry) -> some View {
        Button(role: .destructive) { deleting = entry } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless).help(L10n.text("Удалить запись"))
            .accessibilityLabel(L10n.text("Удалить запись"))
    }
    @ViewBuilder private func copyButtons(_ text: HistoryText, translation: Bool) -> some View {
        if translation { CopyTextButton(text: text.translation, title: L10n.text("Скопировать перевод"), showsTitle: true) }
        CopyTextButton(text: text.original, title: L10n.text("Скопировать оригинал"), showsTitle: true)
    }
    #endif
    private func entryTitle(_ entry: HistoryEntry) -> String {
        if entry.kind == .originalRecording { return L10n.text("Запись оригинала") + " · " + TranslationLanguage.name(entry.source.rawValue) }
        if entry.kind == .originalSpeech { return L10n.text("Озвучка оригинала") + " · " + TranslationLanguage.name(entry.source.rawValue) }
        let prefix = entry.kind == .imageTranslation ? L10n.text("Изображение") + " · " : ""
        return prefix + TranslationLanguage.name(entry.source.rawValue) + " → " + TranslationLanguage.name(entry.target.rawValue)
    }
    private func imageActions(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { if let url = await history.imageURL(entry.id) { openedImage = (entry.id, url) } }
            } label: {
                HistoryImageThumbnail(id: entry.id, store: history.store)
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("Открыть изображение"))
                .accessibilityIdentifier("history.image." + entry.id.uuidString)
            #if os(iOS)
            imageShareButton(entry.id)
            #endif
        }
    }
    private func imageShareButton(_ id: UUID) -> some View {
        Button { shareImage(id) } label: {
            Label(L10n.text("Поделиться изображением"), systemImage: "square.and.arrow.up")
        }.accessibilityIdentifier("history.shareImage." + id.uuidString)
    }
    private func shareImage(_ id: UUID) {
        Task { if let url = await history.imageURL(id) { share = SharedAudio(url: url) } }
    }
    private func closeImage() {
        if let openedImage { try? FileManager.default.removeItem(at: openedImage.url) }
        openedImage = nil
    }
    private func clearShare() { if let share { try? FileManager.default.removeItem(at: share.url) }; share = nil }
}

/// Presentation only. Stored text, clipboard and audio sharing always use the full entry.
enum HistoryPreview {
    static let limit = 240
    static func isLong(_ value: String) -> Bool {
        value.count > limit || value.filter { $0.isNewline }.count > 2
    }
    static func text(_ value: String) -> String {
        guard isLong(value) else { return value }
        let singleLine = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return singleLine.count > limit ? String(singleLine.prefix(limit)) + "…" : singleLine
    }
}
