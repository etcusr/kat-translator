import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import OfflineCore

struct TextTranslationFields: View {
    let session: ConversationPipeline
    @Binding var input: String
    let output: String
    let source: SpeechLanguage?
    let target: SpeechLanguage
    let busy: Bool
    let canSpeakSource: Bool
    let canSpeakTarget: Bool
    let speakingField: String?
    let paused: Bool
    let speed: PlaybackSpeed
    let pauseResume: () -> Void
    let selectSpeed: (PlaybackSpeed) -> Void
    let editing: FocusState<Bool>.Binding
    let clearSource: () -> Void
    let clearTarget: () -> Void
    let speak: (String, SpeechLanguage, String) -> Void
    let stop: () -> Void
    let expandSource: () -> Void
    let expandTarget: () -> Void
    var editorHeight: CGFloat = AppPlatform.editorHeight
    var timing: TranslationTiming?
    var submit: (() -> Void)? = nil
    private var layout: AnyLayout {
        #if os(macOS)
        return AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        #else
        return AnyLayout(VStackLayout(spacing: 16))
        #endif
    }
    var body: some View {
        layout {
            TextFieldPanel(session: session, title: source.map { TranslationLanguage.shortCode($0.rawValue) } ?? L10n.text("Авто"), fullTitle: source.map { TranslationLanguage.name($0.rawValue) } ?? L10n.text("Авто"), language: source, text: input, editable: $input,
                           busy: busy, canSpeak: canSpeakSource, speaking: speakingField == "source",
                           speak: { if let source { speak(input, source, "source") } }, stop: stop,
                           editing: editing, clear: clearSource, paused: paused, speed: speed, pauseResume: pauseResume, selectSpeed: selectSpeed, expand: expandSource, editorHeight: editorHeight, submit: submit)
            TextFieldPanel(session: session, title: TranslationLanguage.shortCode(target.rawValue), fullTitle: TranslationLanguage.name(target.rawValue), language: target, text: output, editable: nil,
                           busy: busy, canSpeak: canSpeakTarget, speaking: speakingField == "target",
                           speak: { speak(output, target, "target") }, stop: stop,
                           editing: editing, clear: clearTarget, paused: paused, speed: speed, pauseResume: pauseResume, selectSpeed: selectSpeed, expand: expandTarget, editorHeight: editorHeight, timing: timing)
        }
    }
}
private struct TextFieldPanel: View {
    #if os(macOS)
    @ObservedObject private var shortcuts = MacShortcutSettings.shared
    #endif
    let session: ConversationPipeline
    let title: String
    let fullTitle: String
    let language: SpeechLanguage?
    let text: String
    let editable: Binding<String>?
    let busy: Bool
    let canSpeak: Bool
    let speaking: Bool
    let speak: () -> Void
    let stop: () -> Void
    let editing: FocusState<Bool>.Binding
    let clear: () -> Void
    let paused: Bool
    let speed: PlaybackSpeed
    let pauseResume: () -> Void
    let selectSpeed: (PlaybackSpeed) -> Void
    let expand: () -> Void
    let editorHeight: CGFloat
    var timing: TranslationTiming?
    var submit: (() -> Void)? = nil
    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var speechHint: String? {
        #if os(macOS)
        return canSpeak ? nil : L10n.text("Озвучка недоступна для выбранного языка или голос не скачан")
        #else
        return nil
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text(title).font(AppPlatform.secondaryFont.weight(.semibold)).foregroundStyle(.secondary)
                    .monospaced().accessibilityLabel(fullTitle)
                    .accessibilityIdentifier(editable == nil ? "text.target.language" : "text.source.language")
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
                ExpandTextButton(enabled: !empty, identifier: editable == nil ? "text.target.expand" : "text.source.expand", action: expand)
                PlaybackControls(active: speaking, paused: paused, disabled: busy || empty || !canSpeak,
                    speed: speed, startLabel: editable == nil ? L10n.text("Озвучить перевод") : L10n.text("Озвучить оригинал"),
                    identifier: editable == nil ? "text.target.playback" : "text.source.playback",
                    start: speak, stop: stop, pauseResume: pauseResume, selectSpeed: selectSpeed, unavailableHint: speechHint)
                    .fixedSize(horizontal: true, vertical: false)
                CopyTextButton(text: text, title: editable == nil ? L10n.text("Скопировать перевод") : L10n.text("Скопировать оригинал"))
                    .accessibilityIdentifier(editable == nil ? "text.copy.target" : "text.copy.source")
                TextShareButton(text: text, language: language, original: editable != nil, session: session).disabled(empty || busy)
                    .accessibilityIdentifier(editable == nil ? "text.share.target" : "text.share.source")
                Button(action: clear) {
                    Image(systemName: AppPlatform.clearSymbol).frame(width: AppPlatform.clearControlSize, height: AppPlatform.clearControlSize)
                }.katCloseControl().disabled(text.isEmpty)
                    .accessibilityLabel(editable == nil ? L10n.text("Очистить перевод") : L10n.text("Очистить оригинал"))
                    .accessibilityIdentifier(editable == nil ? "text.clear.target" : "text.clear.source")
            }
            .katDesktopIconFont()
            #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                if let editable {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: editable).scrollContentBackground(.hidden)
                            .font(AppPlatform.translationFont).lineSpacing(4)
                            .accessibilityLabel(L10n.text("Текст оригинала")).disabled(busy).focused(editing)
                            .background(MacTextSubmitHandler(focused: editing.wrappedValue, busy: busy) { submit?() })
                        if text.isEmpty {
                            Text(L10n.text("Введите текст"))
                                .foregroundStyle(.secondary).padding(.horizontal, 5)
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("text.source.placeholder")
                        }
                    }
                } else {
                    ScrollView {
                        Text(empty ? L10n.text("Здесь появится перевод") : text).foregroundStyle(empty ? .secondary : .primary)
                            .font(AppPlatform.translationFont)
                            .frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled)
                            .padding(.horizontal, 5)
                            .accessibilityIdentifier("text.translation.text")
                    }
                }
            }.font(AppPlatform.translationFont).lineSpacing(4)
                .frame(maxWidth: .infinity).frame(height: editorHeight, alignment: .top)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(editable == nil ? "text.target.body" : "text.source.body")
            if let timing { TranslationTimingView(timing: timing, identifier: "text.timing") }
            #else
            if let timing { TranslationTimingView(timing: timing, identifier: "text.timing") }
            if !canSpeak { Text(L10n.text("Озвучка недоступна для выбранного языка или голос не скачан")).font(.caption2).foregroundStyle(.secondary) }
            if let editable {
                TextEditor(text: editable).frame(minHeight: AppPlatform.editorHeight, maxHeight: AppPlatform.editorHeight + 80).scrollContentBackground(.hidden)
                    .font(AppPlatform.translationFont)
                    .accessibilityLabel(L10n.text("Текст оригинала")).disabled(busy).focused(editing)
            } else {
                Text(empty ? L10n.text("Здесь появится перевод") : text).foregroundStyle(empty ? .secondary : .primary)
                    .font(AppPlatform.translationFont)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading).textSelection(.enabled)
                    .accessibilityIdentifier("text.translation.text")
            }
            #endif
            HStack(alignment: .bottom, spacing: 12) {
                #if os(macOS)
                if editable != nil {
                    Text(shortcuts.submitHint)
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                        .lineLimit(2).help(shortcuts.submitHint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("text.submit.hint")
                }
                #endif
                TextCharacterCount(text: text, identifier: editable == nil ? "text.target.count" : "text.source.count")
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            #if os(macOS)
            .frame(minHeight: 36, alignment: .bottom)
            #endif
        }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }
}
