import Foundation
import AVFoundation
import ImageIO

public struct HistoryPolicy: Codable, Sendable, Equatable {
    public var textCount: Int, audioCount: Int, textDays: Int, audioDays: Int
    private var storedImageCount: Int?, storedImageDays: Int?
    public var imageCount: Int { storedImageCount ?? 20 }
    public var imageDays: Int { storedImageDays ?? 30 }
    public init(textCount: Int = 100, audioCount: Int = 10, textDays: Int = 30, audioDays: Int = 30, imageCount: Int = 20, imageDays: Int = 30) {
        storedImageCount = max(0, imageCount); storedImageDays = min(365, max(0, imageDays))
        self.textCount = max(0, textCount); self.audioCount = max(0, audioCount)
        self.textDays = min(365, max(0, textDays)); self.audioDays = min(365, max(0, audioDays))
    }
}
public struct HistoryText: Codable, Sendable, Equatable {
    public let original: String, translation: String
}
public struct HistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case translation, originalSpeech, originalRecording, imageTranslation }
    private var storedKind: Kind?
    public var kind: Kind { storedKind ?? .translation }
    public var isOriginalAudio: Bool { kind == .originalSpeech || kind == .originalRecording }
    public let id: UUID, createdAt: Date, source: SpeechLanguage
    public var text: HistoryText?
    public var hasAudio: Bool
    private var storedHasImage: Bool?
    public var hasImage: Bool { get { storedHasImage ?? false } set { storedHasImage = newValue ? true : nil } }
    private var storedTarget: SpeechLanguage?
    public var target: SpeechLanguage { storedTarget ?? source.opposite }
    public init(id: UUID, createdAt: Date, source: SpeechLanguage, text: HistoryText?, hasAudio: Bool, target: SpeechLanguage? = nil, kind: Kind = .translation, hasImage: Bool = false) {
        storedHasImage = hasImage ? true : nil
        self.id = id; self.createdAt = createdAt; self.source = source; self.text = text; self.hasAudio = hasAudio; self.storedTarget = target; self.storedKind = kind == .translation ? nil : kind
    }
}
public protocol TranslationArchive: Sendable {
    func saveOriginalRecording(_ audio: URL, text: String, language: SpeechLanguage) async throws -> UUID?
    func saveOriginalSpeech(text: String, language: SpeechLanguage) async throws -> UUID?
    func save(original: String, translation: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> UUID?
    func appendAudio(_ pcm: SpeechPCM, to id: UUID) async throws
    func finishAudio(_ id: UUID) async throws
    func abortAudio(_ id: UUID) async
    func copyAudio(_ id: UUID, into directory: URL) async throws -> URL
}
public enum HistoryError: LocalizedError {
    case missing, corrupt, invalidAudio
    public var errorDescription: String? {
        switch self {
        case .missing: return L10n.text("Эта запись уже удалена из истории.")
        case .corrupt: return L10n.text("Не удалось прочитать историю. Существующий файл сохранён без изменений.")
        case .invalidAudio: return L10n.text("Не удалось сохранить озвучку. Текст перевода доступен отдельно.")
        }
    }
}
public actor TranslationHistory: TranslationArchive {
    private let root: URL
    private let indexWriter: (@Sendable (Data, URL) throws -> Void)?
    private var entries: [HistoryEntry] = []
    private var loaded = false
    private var policy = HistoryPolicy()
    private var recordText = true
    private var recordAudio = true
    private var recordImages = true
    private var drafts: [UUID: AVAudioFile] = [:]
    public init(root: URL) { self.root = root; indexWriter = nil }
    init(root: URL, indexWriter: @escaping @Sendable (Data, URL) throws -> Void) {
        self.root = root; self.indexWriter = indexWriter
    }
    private var index: URL { root.appendingPathComponent("history.json") }
    private func audioURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".m4a") }
    /// Camera photos are stored as JPEG, screen captures and older entries as PNG (audit 22.10, iOS C1 / O18).
    private static let imageExtensions = ["jpg", "png"]
    private func imageURL(_ id: UUID, extension type: String? = nil) -> URL {
        if let type { return root.appendingPathComponent(id.uuidString + "." + type) }
        return Self.imageExtensions.map { root.appendingPathComponent(id.uuidString + "." + $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? root.appendingPathComponent(id.uuidString + ".png")
    }
    private func draftURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".partial.m4a") }
    private func load() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var recovery: URL?
        if FileManager.default.fileExists(atPath: index.path) {
            // A read failure (for example a protected file while the device is locked) is not corruption.
            let data = try Data(contentsOf: index)
            if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) { entries = decoded }
            else {
                // An unreadable index (damage, or entries written by a newer build) must not block saving
                // or clearing forever. Keep its exact bytes, then continue with every readable entry.
                let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
                try writeProtected(data, to: root.appendingPathComponent("history.unreadable-\(stamp).json"))
                entries = (try? JSONDecoder().decode([LenientHistoryEntry].self, from: data))?.compactMap(\.entry) ?? []
                recovery = root.appendingPathComponent("Recovered-\(stamp)", isDirectory: true)
            }
        }
        // A killed writer never becomes a finished recording. Remove only files owned by this store.
        // After recovering an unreadable index, unowned media may belong to skipped entries: keep it aside.
        func discard(_ url: URL) throws {
            guard let recovery else { try? FileManager.default.removeItem(at: url); return }
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: recovery.appendingPathComponent(url.lastPathComponent))
        }
        let owned = Set(entries.filter(\.hasAudio).map { $0.id.uuidString + ".m4a" })
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if url.pathExtension == "m4a", !owned.contains(url.lastPathComponent) { try discard(url) }
        }
        let ownedImages = Set(entries.filter(\.hasImage).map { $0.id.uuidString })
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where Self.imageExtensions.contains(url.pathExtension) && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
                && !ownedImages.contains(url.deletingPathExtension().lastPathComponent) {
            try discard(url)
        }
        for i in entries.indices where entries[i].hasImage && !FileManager.default.fileExists(atPath: imageURL(entries[i].id).path) { entries[i].hasImage = false }
        for i in entries.indices where entries[i].hasAudio && !FileManager.default.fileExists(atPath: audioURL(entries[i].id).path) { entries[i].hasAudio = false }
        loaded = true
    }
    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
    private func persist(_ next: [HistoryEntry]) throws {
        let data = try JSONEncoder().encode(next)
        if let indexWriter { try indexWriter(data, index) } else { try writeProtected(data, to: index) }
        entries = next
    }
    public func setRecording(text: Bool, audio: Bool, images: Bool = true) {
        recordText = text; recordAudio = audio; recordImages = images
        if !audio { for id in Array(drafts.keys) { abortAudio(id) } }
    }
    public func list() throws -> [HistoryEntry] {
        try load()
        return entries.filter { ($0.text != nil || $0.hasAudio || $0.hasImage) && (!$0.isOriginalAudio || $0.hasAudio) }.sorted { $0.createdAt > $1.createdAt }
    }
    /// Commit a rendered translation and its text together. The source file is never modified.
    public func saveImage(_ png: Data, original: String, translation: String, source: SpeechLanguage, target: SpeechLanguage) throws -> UUID? {
        guard recordImages || recordText else { return nil }
        try load()
        let id = UUID()
        let decoded = CGImageSourceCreateWithData(png as CFData, nil)
        let type = decoded.flatMap { CGImageSourceGetType($0) as String? }
        let url = imageURL(id, extension: type == "public.jpeg" ? "jpg" : "png")
        if recordImages {
            guard png.count <= 50 * 1024 * 1024, let decoded, type == "public.png" || type == "public.jpeg",
                  CGImageSourceCreateImageAtIndex(decoded, 0, nil) != nil else { throw HistoryError.corrupt }
            #if os(iOS)
            try png.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try png.write(to: url, options: .atomic)
            #endif
        }
        let entry = HistoryEntry(id: id, createdAt: Date(), source: source,
            text: recordText ? HistoryText(original: original, translation: translation) : nil,
            hasAudio: false, target: target, kind: .imageTranslation, hasImage: recordImages)
        do { try persist(entries + [entry]) }
        catch { if recordImages { try? FileManager.default.removeItem(at: url) }; throw error }
        try prune()
        return id
    }
    public func imageData(_ id: UUID) throws -> Data {
        try load()
        guard entries.contains(where: { $0.id == id && $0.hasImage }) else { throw HistoryError.missing }
        return try Data(contentsOf: imageURL(id))
    }
    public func copyImage(_ id: UUID, into directory: URL) throws -> URL {
        try load()
        guard entries.contains(where: { $0.id == id && $0.hasImage }) else { throw HistoryError.missing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = imageURL(id)
        let url = directory.appendingPathComponent("Translated-image-" + UUID().uuidString + "." + stored.pathExtension)
        try FileManager.default.copyItem(at: stored, to: url)
        return url
    }
    public func saveOriginalSpeech(text: String, language: SpeechLanguage) throws -> UUID? {
        guard recordAudio else { return nil }
        try load()
        let id = UUID(), now = Date()
        let entry = HistoryEntry(id: id, createdAt: now, source: language,
            text: recordText ? HistoryText(original: text, translation: "") : nil,
            hasAudio: false, target: language, kind: .originalSpeech)
        try persist(entries + [entry])
        try prune(now: now, keepingPendingAudio: id)
        return id
    }
    public func saveOriginalRecording(_ audio: URL, text: String, language: SpeechLanguage) throws -> UUID? {
        guard recordAudio else { return nil }
        try load()
        guard try AVAudioFile(forReading: audio).length > 0 else { throw HistoryError.invalidAudio }
        let id = UUID(), now = Date(), destination = audioURL(id)
        try FileManager.default.copyItem(at: audio, to: destination)
        let entry = HistoryEntry(id: id, createdAt: now, source: language,
            text: recordText ? HistoryText(original: text, translation: "") : nil,
            hasAudio: true, target: language, kind: .originalRecording)
        do { try persist(entries + [entry]) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        try prune(now: now)
        return id
    }
    public func save(original: String, translation: String, source: SpeechLanguage, target: SpeechLanguage) throws -> UUID? {
        try save(original: original, translation: translation, source: source, now: Date(), target: target)
    }
    public func save(original: String, translation: String, source: SpeechLanguage) throws -> UUID? {
        try save(original: original, translation: translation, source: source, now: Date())
    }
    public func save(original: String, translation: String, source: SpeechLanguage, now: Date, target: SpeechLanguage? = nil) throws -> UUID? {
        guard recordText || recordAudio else { return nil }
        try load()
        let id = UUID()
        let text = recordText ? HistoryText(original: original, translation: translation) : nil
        let entry = HistoryEntry(id: id, createdAt: now, source: source, text: text, hasAudio: false, target: target)
        // An audio-only entry contains metadata, never the text; publish it once audio is complete.
        try persist(entries + [entry]); try prune(now: now, keepingPendingAudio: recordAudio ? id : nil); return id
    }
    public func setPolicy(_ value: HistoryPolicy, now: Date = Date()) throws {
        try load(); policy = value; try prune(now: now)
    }
    public func prune(now: Date = Date()) throws { try prune(now: now, keepingPendingAudio: nil) }
    private func prune(now: Date, keepingPendingAudio pending: UUID?) throws {
        try load()
        var next = entries.sorted { $0.createdAt > $1.createdAt }
        var texts = 0, audios = 0, images = 0; var removedAudio: [UUID] = [], removedImages: [UUID] = []
        for i in next.indices {
            if drafts[next[i].id] != nil { continue }
            let age = now.timeIntervalSince(next[i].createdAt)
            if next[i].text != nil {
                texts += 1
                if (policy.textCount > 0 && texts > policy.textCount) || (policy.textDays > 0 && age >= Double(policy.textDays) * 86400) { next[i].text = nil }
            }
            if next[i].hasImage {
                images += 1
                if (policy.imageCount > 0 && images > policy.imageCount) || (policy.imageDays > 0 && age >= Double(policy.imageDays) * 86400) {
                    next[i].hasImage = false; removedImages.append(next[i].id)
                }
            }
            if next[i].hasAudio {
                audios += 1
                if (policy.audioCount > 0 && audios > policy.audioCount) || (policy.audioDays > 0 && age >= Double(policy.audioDays) * 86400) {
                    next[i].hasAudio = false; removedAudio.append(next[i].id)
                }
            }
        }
        next.removeAll { ($0.text == nil || $0.isOriginalAudio) && !$0.hasAudio && !$0.hasImage && $0.id != pending && drafts[$0.id] == nil }
        try persist(next)
        for id in removedImages { try? FileManager.default.removeItem(at: imageURL(id)) }
        for id in removedAudio { try? FileManager.default.removeItem(at: audioURL(id)) }
    }
    public func appendAudio(_ pcm: SpeechPCM, to id: UUID) throws {
        guard recordAudio else { return }
        try load()
        guard entries.contains(where: { $0.id == id }) else { throw HistoryError.missing }
        guard SpeechAudioWriter.valid(pcm) else { throw HistoryError.invalidAudio }
        if drafts[id] == nil {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: pcm.sampleRate,
                AVNumberOfChannelsKey: 1]
            drafts[id] = try AVAudioFile(forWriting: draftURL(id), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            #if os(iOS)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: draftURL(id).path)
            #endif
        }
        guard let file = drafts[id] else { throw HistoryError.invalidAudio }
        try SpeechAudioWriter.write(pcm, to: file)
    }
    public func finishAudio(_ id: UUID) throws {
        guard recordAudio else { abortAudio(id); return }
        guard drafts.removeValue(forKey: id) != nil, let i = entries.firstIndex(where: { $0.id == id }) else { throw HistoryError.missing }
        let url = audioURL(id)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.moveItem(at: draftURL(id), to: url)
            var next = entries; next[i].hasAudio = true; try persist(next)
        } catch { try? FileManager.default.removeItem(at: url); throw error }
        // The audio is committed. A failed retention write must not roll it back.
        try prune()
    }
    public func abortAudio(_ id: UUID) {
        drafts[id] = nil; try? FileManager.default.removeItem(at: draftURL(id))
        if entries.contains(where: { $0.id == id && $0.kind == .originalSpeech && !$0.hasAudio }) {
            try? persist(entries.filter { $0.id != id })
        }
    }
    public func remove(_ id: UUID) throws {
        try load(); abortAudio(id); try persist(entries.filter { $0.id != id }); try? FileManager.default.removeItem(at: audioURL(id)); try? FileManager.default.removeItem(at: imageURL(id))
    }
    public func removeAll() throws {
        try load()
        try persist([])
        drafts.removeAll() // Close partial writers before deleting their files.
        // Include orphaned files from an interrupted clear; never remove unrelated files/subdirectories.
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where (Self.imageExtensions + ["m4a"]).contains(url.pathExtension) {
            let stem = url.deletingPathExtension().lastPathComponent
            let id = stem.hasSuffix(".partial") ? String(stem.dropLast(8)) : stem
            if UUID(uuidString: id) != nil { try FileManager.default.removeItem(at: url) }
        }
        // Clearing history also clears copies kept aside while recovering an unreadable index.
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            if (name.hasPrefix("history.unreadable-") && url.pathExtension == "json") || name.hasPrefix("Recovered-") {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    /// A private copy stays valid even if retention removes the original while the share sheet is open.
    public func copyAudio(_ id: UUID, into directory: URL) throws -> URL {
        try load()
        guard let entry = entries.first(where: { $0.id == id && $0.hasAudio }) else { throw HistoryError.missing }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefix = entry.kind == .originalRecording ? "Original-recording-" : entry.kind == .originalSpeech ? "Original-speech-" : "Translation-"
        let url = directory.appendingPathComponent(prefix + UUID().uuidString + ".m4a")
        try FileManager.default.copyItem(at: audioURL(id), to: url); return url
    }
}

/// Decodes one index entry without failing the whole index (for example an unknown newer kind).
private struct LenientHistoryEntry: Decodable {
    let entry: HistoryEntry?
    init(from decoder: Decoder) throws { entry = try? HistoryEntry(from: decoder) }
}
/// Shared mono AAC writer for history and share copies. Long speech is written in one-minute slices,
/// so a complete streamed translation is never rejected because of its length.
enum SpeechAudioWriter {
    static let maximumSeconds = 3600
    static func valid(_ pcm: SpeechPCM) -> Bool {
        pcm.sampleRate > 0 && !pcm.samples.isEmpty && pcm.samples.count <= pcm.sampleRate * maximumSeconds && pcm.samples.allSatisfy(\.isFinite)
    }
    static func write(_ pcm: SpeechPCM, to file: AVAudioFile) throws {
        guard valid(pcm), file.processingFormat.sampleRate == Double(pcm.sampleRate) else { throw HistoryError.invalidAudio }
        let slice = pcm.sampleRate * 60
        var offset = 0
        while offset < pcm.samples.count {
            let count = min(slice, pcm.samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let samples = buffer.floatChannelData?[0] else { throw HistoryError.invalidAudio }
            buffer.frameLength = buffer.frameCapacity
            pcm.samples.withUnsafeBufferPointer { samples.update(from: $0.baseAddress! + offset, count: count) }
            try file.write(from: buffer)
            offset += count
        }
    }
}
