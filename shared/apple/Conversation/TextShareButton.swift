import SwiftUI
import OfflineCore

/// Shares the selected field and its completed recording, if one exists.
struct TextShareButton: View {
    let text: String
    let language: SpeechLanguage?
    let original: Bool
    let session: ConversationPipeline
    #if os(iOS)
    @State private var payload: TextSharePayload?
    @State private var exportURL: URL?
    @State private var preparing = false
    @State private var error: String?
    #endif
    var body: some View {
        #if os(macOS)
        MacShareButton(text: text, prepareFile: { try await audioCopy() })
        #else
        Button {
            guard !preparing else { return }
            preparing = true
            let selectedText = text
            Task {
                defer { preparing = false }
                do {
                    let audio = try await audioCopy()
                    exportURL = audio
                    payload = TextSharePayload(text: selectedText, audio: audio)
                }
                catch { self.error = error.localizedDescription }
            }
        } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 44) }
            .accessibilityLabel(L10n.text("Поделиться")).disabled(preparing)
            .sheet(item: $payload, onDismiss: clear) { value in TextShareSheet(payload: value) { clear() } }
            .alert(L10n.text("Поделиться"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        #endif
    }
    private func audioCopy() async throws -> URL? {
        guard let language else { return nil }
        return try await session.copyTextSpeechForSharing(text: text, language: language, original: original, into: TextShareExport.directory())
    }
    #if os(iOS)
    private func clear() {
        if let audio = exportURL { try? FileManager.default.removeItem(at: audio.deletingLastPathComponent()) }
        exportURL = nil; payload = nil
    }
    #endif
}

/// Shares may outlive the picker (especially external macOS apps); expire only our own exports.
enum TextShareExport {
    static func directory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KatTextShare", isDirectory: true)
        if let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for url in urls where UUID(uuidString: url.lastPathComponent) != nil {
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: url) }
            }
        }
        return root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
#if os(iOS)
import UIKit
private struct TextSharePayload: Identifiable { let id = UUID(); let text: String; let audio: URL? }
private struct TextShareSheet: UIViewControllerRepresentable {
    let payload: TextSharePayload
    let done: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.text]
        if let audio = payload.audio { items.append(audio) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in done() }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

@MainActor enum TemporarySpeechFiles {
    private static var prepared = false
    static func prepareForLaunch() {
        guard !prepared else { return }; prepared = true
        removeExports()
    }
    /// Only app-owned temporary files; the persistent history directory is never touched.
    static func removeExports(in temporary: URL = FileManager.default.temporaryDirectory) {
        for name in ["KatTextSpeech", "KatVoiceRecording", "KatSpeechReplay", "KatTextShare", "KatShare", "HistoryExports"] {
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(name))
        }
    }
}

/// Send the current Voice audio file; text has its own Copy button.
struct VoiceAudioShareButton: View {
    let session: ConversationPipeline
    var original = true
    private var title: String { original ? L10n.text("Поделиться записью оригинала") : L10n.text("Поделиться озвучкой") }
    #if os(iOS)
    @State private var shared: SharedAudio?
    @State private var export: URL?
    @State private var error: String?
    #endif
    var body: some View {
        #if os(macOS)
        MacShareButton(prepareFile: { try audioCopy() }, title: title)
        #else
        Button {
            do {
                if let url = try audioCopy() { export = url; shared = SharedAudio(url: url) }
            } catch { self.error = error.localizedDescription }
        } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 44) }
            .accessibilityLabel(title)
            .sheet(item: $shared, onDismiss: clear) { item in AudioShareSheet(item: item, done: clear) }
            .alert(L10n.text("Поделиться"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        #endif
    }
    private func audioCopy() throws -> URL? {
        try original ? session.copyOriginalRecording(into: TextShareExport.directory())
            : session.copyVoiceTranslationSpeech(into: TextShareExport.directory())
    }
    #if os(iOS)
    private func clear() {
        if let export { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        export = nil; shared = nil
    }
    #endif
}
