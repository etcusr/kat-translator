"""Enable the existing audio-file pipeline only inside the disposable iOS lab."""
import argparse
import plistlib
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("snapshot", type=Path)
a = p.parse_args()
root = a.snapshot.resolve()
assert ".build" in root.parts and root.name == "source" and not (root / ".git").exists()
info = root / "apps/ios/Info.plist"
metadata = plistlib.loads(info.read_bytes())
assert metadata["CFBundleDisplayName"] == "Kat Voice Lab"


def replace(path, old, new):
    f = root / path
    text = f.read_text()
    assert text.count(old) == 1, (path, old, text.count(old))
    f.write_text(text.replace(old, new, 1))


replace("shared/apple/Conversation/AppModel.swift",
        "    #if os(macOS)\n    func importAudioFile",
        "    func importAudioFile")
replace("shared/apple/Conversation/AppModel.swift",
        "    #endif\n    func translateText", "    func translateText")
replace("shared/apple/Conversation/AppModel.swift",
        "let audio = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }",
        """let audio = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            ResearchTrace.decodedFile(audio)""")
replace("shared/apple/Conversation/AppModel.swift",
        '                              inputMode: "audio-file", thermal: Self.thermalState)\n            await history.refresh()',
        '''                              inputMode: "audio-file", thermal: Self.thermalState)
            await history.refresh()
            if id == interactionID, inputMode == .voice { await synchronizeRecognition() }
            ResearchTrace.finished(self)''')
replace("shared/apple/Conversation/ConversationView.swift",
        "                #if os(macOS)\n                .fileImporter",
        "                .fileImporter")
replace("shared/apple/Conversation/ConversationView.swift",
        "                #endif\n                .katFullScreenCover",
        "                .katFullScreenCover")
replace("shared/apple/Audio/VoiceStageControls.swift",
        "    @ObservedObject var model: AppModel",
        '    @AppStorage("showTechnicalInfo") private var showTechnicalInfo = false\n    @ObservedObject var model: AppModel')
replace("shared/apple/Audio/VoiceStageControls.swift",
        "                if busy {\n                    VStack(spacing: 8)",
        '''                #if os(iOS)
                if showTechnicalInfo && !busy {
                    Button(action: importAudio) {
                        Label("Распознать аудиофайл", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.voiceLanguageIssue != nil)
                    .accessibilityIdentifier("voice.import")
                    Text("Диагностика · распознавание из файла")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #endif
                if busy {
                    VStack(spacing: 8)''')
# Expose only this disposable application's documents in the system file picker.
metadata["UIFileSharingEnabled"] = True
metadata["LSSupportsOpeningDocumentsInPlace"] = True
info.write_bytes(plistlib.dumps(metadata))
print("Diagnostic file import enabled in", root)
