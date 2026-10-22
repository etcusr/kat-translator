import Foundation
import AVFoundation

/// Two temporary, completed recordings for one workspace, independent of history retention.
@MainActor final class TextSpeechShareCache {
    private struct Entry { let text: String; let language: SpeechLanguage; let url: URL }
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("KatTextSpeech").appendingPathComponent(UUID().uuidString)
    private var entries: [Bool: Entry] = [:]
    private var pending: Entry?
    private var pendingOriginal = false
    private var writer: AVAudioFile?
    func begin(text: String, language: SpeechLanguage, original: Bool) throws {
        abort()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        pending = Entry(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language, url: root.appendingPathComponent(UUID().uuidString + ".m4a"))
        pendingOriginal = original
    }
    func append(_ pcm: SpeechPCM) throws {
        guard let pending else { return }
        guard SpeechAudioWriter.valid(pcm) else { throw HistoryError.invalidAudio }
        if writer == nil {
            writer = try AVAudioFile(forWriting: pending.url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: pcm.sampleRate, AVNumberOfChannelsKey: 1], commonFormat: .pcmFormatFloat32, interleaved: false)
            #if os(iOS)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: pending.url.path)
            #endif
        }
        guard let writer else { throw HistoryError.invalidAudio }
        try SpeechAudioWriter.write(pcm, to: writer)
    }
    func finish() {
        guard let pending, writer != nil else { abort(); return }
        writer = nil // Finalize the AAC container before exposing it.
        if let old = entries[pendingOriginal] { try? FileManager.default.removeItem(at: old.url) }
        entries[pendingOriginal] = pending; self.pending = nil
    }
    func abort() {
        writer = nil
        if let pending { try? FileManager.default.removeItem(at: pending.url) }
        pending = nil
    }
    func contains(text: String, language: SpeechLanguage, original: Bool) -> Bool {
        guard let entry = entries[original] else { return false }
        return entry.text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && entry.language == language && FileManager.default.fileExists(atPath: entry.url.path)
    }
    func copy(text: String, language: SpeechLanguage, original: Bool, into directory: URL) throws -> URL? {
        guard let entry = entries[original], entry.text == text.trimmingCharacters(in: .whitespacesAndNewlines), entry.language == language,
              FileManager.default.fileExists(atPath: entry.url.path) else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = directory.appendingPathComponent(original ? "Kat-original.m4a" : "Kat-translation.m4a")
        try FileManager.default.copyItem(at: entry.url, to: result)
        return result
    }
    func clear() { abort(); entries = [:]; try? FileManager.default.removeItem(at: root) }
    deinit { try? FileManager.default.removeItem(at: root) }
}
