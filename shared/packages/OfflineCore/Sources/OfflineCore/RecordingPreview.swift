import Foundation

/// Runs on the conversion queue. Sample positions exclude user-paused time.
public struct RecordingPreviewBoundary {
    public private(set) var lastSpeechEnd = 0
    private var position = 0
    private var lastBoundary = 0
    private var pendingSpeech = false
    public init() {}
    public mutating func observe(speech: Bool, sampleCount: Int) -> Int? {
        position += max(0, sampleCount)
        if speech { lastSpeechEnd = position; pendingSpeech = true }
        guard pendingSpeech, position - lastSpeechEnd >= 16_000,
              position - lastBoundary >= 32_000 else { return nil }
        pendingSpeech = false; lastBoundary = position
        return position
    }
}
public struct RecordingPreviewSpeech: Sendable {
    public let text: String
    public let pcm: SpeechPCM
    public let seconds: Double
    public init(text: String, pcm: SpeechPCM, seconds: Double) { self.text = text; self.pcm = pcm; self.seconds = seconds }
}
public struct RecordingPreviewResult: Sendable {
    public var committedSamples = 0
    public var sourceText = ""
    public var translatedText = ""
    public var source: SpeechLanguage?
    public var target: SpeechLanguage?
    public var firstSpeech: RecordingPreviewSpeech?
    public var asrSeconds = 0.0, mtSeconds = 0.0, processingSeconds = 0.0
    public var blocks = 0
    public var translations: [RecordingPreviewBlock] = []
    public var fallbackReason: String?
    public init() {}
}

/// Owns no model or microphone. Only one job and one coalesced pending boundary.
@MainActor public final class RecordingPreviewCoordinator {
    public typealias Snapshot = @MainActor (Range<Int>) async throws -> CapturedAudio
    private let snapshot: Snapshot
    private let recognize: @MainActor (CapturedAudio, SpeechLanguage?) async throws -> ASRResult
    private let translate: @MainActor (String, SpeechLanguage, SpeechLanguage) async throws -> TranslationResult
    private let prepareSpeech: (@MainActor (String, SpeechLanguage) async throws -> RecordingPreviewSpeech?)?
    private let publish: @MainActor (RecordingPreviewResult) -> Void
    private let requestedSource: SpeechLanguage?
    private let requestedTarget: SpeechLanguage
    private var result = RecordingPreviewResult()
    private var pendingEnd: Int?
    private var job: Task<Void, Never>?
    private var closed = false, cancelled = false, suspended = false
    public init(source: SpeechLanguage?, target: SpeechLanguage, snapshot: @escaping Snapshot,
                recognize: @escaping @MainActor (CapturedAudio, SpeechLanguage?) async throws -> ASRResult,
                translate: @escaping @MainActor (String, SpeechLanguage, SpeechLanguage) async throws -> TranslationResult,
                prepareSpeech: (@MainActor (String, SpeechLanguage) async throws -> RecordingPreviewSpeech?)?,
                publish: @escaping @MainActor (RecordingPreviewResult) -> Void) {
        requestedSource = source; requestedTarget = target; self.snapshot = snapshot
        self.recognize = recognize; self.translate = translate; self.prepareSpeech = prepareSpeech; self.publish = publish
    }
    public func offer(end: Int) {
        guard !closed, !suspended, end > result.committedSamples else { return }
        pendingEnd = max(end, pendingEnd ?? 0)
        if job == nil { job = Task { await drain() } }
    }
    public func suspend(reason: String) {
        suspended = true; pendingEnd = nil; result.fallbackReason = reason
        job?.cancel() // Preserve committed blocks, cancel only the speculative work in flight.
        if reason == "memory-warning" { result.firstSpeech = nil }
    }
    public func cancel() { cancelled = true; closed = true; pendingEnd = nil; job?.cancel() }
    public func waitForIdle() async { await job?.value }
    public func finish() async -> RecordingPreviewResult { closed = true; await job?.value; return result }
    private func check() throws { try Task.checkCancellation(); if cancelled { throw CancellationError() } }
    private func drain() async {
        defer { job = nil }
        while let end = pendingEnd, !cancelled, !suspended {
            pendingEnd = nil
            guard end > result.committedSamples else { continue }
            let start = ProcessInfo.processInfo.systemUptime
            defer { result.processingSeconds += ProcessInfo.processInfo.systemUptime - start }
            do {
                let audio = try await snapshot(result.committedSamples..<end)
                try check()
                let asr = try await recognize(audio, result.source ?? requestedSource)
                try check(); result.asrSeconds += asr.processingSeconds
                let text = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, let last = text.last, ".!?。！？".contains(last) else { continue }
                let source = result.source ?? requestedSource ?? asr.language
                let target = requestedTarget
                let mt = source == target ? TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 0)
                    : try await translate(text, source, target)
                try check()
                let translated = mt.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { throw PipelineError.inference }
                result.source = source; result.target = target
                result.sourceText = [result.sourceText, text].filter { !$0.isEmpty }.joined(separator: " ")
                result.translatedText = [result.translatedText, translated].filter { !$0.isEmpty }.joined(separator: " ")
                result.committedSamples = end; result.mtSeconds += mt.processingSeconds; result.blocks += 1
                result.translations.append(RecordingPreviewBlock(source: text, translation: translated))
                publish(result)
                // Prefer already queued recognition over optional speculative speech.
                if result.firstSpeech == nil, pendingEnd == nil, !suspended, let prepareSpeech {
                    do {
                        let prepared = try await prepareSpeech(result.translatedText, target)
                        try check(); result.firstSpeech = prepared
                    } catch is CancellationError { throw CancellationError() }
                    catch { /* A TTS failure must not discard a valid translation. */ }
                }
            } catch is CancellationError { return }
            catch { result.fallbackReason = "preview-error"; suspended = true; pendingEnd = nil }
        }
    }
}
