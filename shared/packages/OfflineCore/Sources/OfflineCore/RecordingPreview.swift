import Foundation

/// Runs on the conversion queue. Sample positions exclude user-paused time.
public struct RecordingPreviewBoundary {
    public private(set) var lastSpeechEnd = 0
    public private(set) var endsInSilence = false
    private var position = 0
    private var lastBoundary = 0
    private var pendingSpeech = false
    private var pendingQuietConfirmation = false
    public init() {}
    public mutating func observe(speech: Bool, sampleCount: Int) -> Int? {
        position += max(0, sampleCount)
        if speech { lastSpeechEnd = position; pendingSpeech = true; pendingQuietConfirmation = true }
        // A VAD speech pause triggers recognition; the coordinator decides whether
        // the recognized sentence is finished. Never split on a wall-clock deadline.
        let quietConfirmation = pendingQuietConfirmation && position - lastSpeechEnd >= 16_000
        let briefPause = pendingSpeech && position - lastSpeechEnd >= 2_560 && position - lastBoundary >= 32_000
        guard quietConfirmation || briefPause else { return nil }
        endsInSilence = quietConfirmation
        if quietConfirmation { pendingQuietConfirmation = false }
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
    private let trace: @MainActor (String) -> Void
    private let requestedSource: SpeechLanguage?
    private let requestedTarget: SpeechLanguage
    private var result = RecordingPreviewResult()
    private var pendingEnd: (end: Int, quiet: Bool)?
    private var previousTranscript = ""
    private var previousSentenceEnds: [(sample: Int, tail: String)] = []
    private var job: Task<Void, Never>?
    private var closed = false, cancelled = false, suspended = false
    public init(source: SpeechLanguage?, target: SpeechLanguage, snapshot: @escaping Snapshot,
                recognize: @escaping @MainActor (CapturedAudio, SpeechLanguage?) async throws -> ASRResult,
                translate: @escaping @MainActor (String, SpeechLanguage, SpeechLanguage) async throws -> TranslationResult,
                prepareSpeech: (@MainActor (String, SpeechLanguage) async throws -> RecordingPreviewSpeech?)?,
                publish: @escaping @MainActor (RecordingPreviewResult) -> Void,
                trace: @escaping @MainActor (String) -> Void = { _ in }) {
        requestedSource = source; requestedTarget = target; self.snapshot = snapshot
        self.recognize = recognize; self.translate = translate; self.prepareSpeech = prepareSpeech; self.publish = publish; self.trace = trace
    }
    public func offer(end: Int, endsInSilence: Bool = true) {
        guard !closed, !suspended, end > result.committedSamples else { return }
        if end >= (pendingEnd?.end ?? 0) { pendingEnd = (end, endsInSilence) }
        if job == nil { job = Task { await drain() } }
    }
    public func suspend(reason: String) {
        trace("preview.suspend." + reason)
        suspended = true; pendingEnd = nil; result.fallbackReason = reason
        job?.cancel() // Preserve committed blocks, cancel only the speculative work in flight.
        if reason == "memory-warning" { result.firstSpeech = nil }
    }
    public func cancel() { cancelled = true; closed = true; pendingEnd = nil; job?.cancel() }
    public func waitForIdle() async { await job?.value }
    public func finish() async -> RecordingPreviewResult { closed = true; await job?.value; return result }
    private func check() throws { try Task.checkCancellation(); if cancelled { throw CancellationError() } }
    /// A brief VAD pause can occur inside a sentence. Commit only a timestamped prefix
    /// that survived another recognition pass and has audio after its end.
    private func completedPrefix(_ asr: ASRResult, sampleCount: Int, quiet: Bool) -> (text: String, samples: Int)? {
        let text = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        func complete(_ value: String) -> Bool { value.last.map { ".!?。！？".contains($0) } ?? false }
        func key(_ value: String) -> String { value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        // Backends without timestamps retain their silence-based path; an arbitrary
        // polling deadline must never consume their whole unfinished audio window.
        guard !asr.segments.isEmpty else { return quiet && complete(text) ? (text, sampleCount) : nil }
        let segmentsText = asr.segments.map(\.text).joined()
        guard key(segmentsText) == key(text) else { return nil }
        var prefix = "", previousEnd = 0
        var selected: (text: String, samples: Int)?
        var observed: [(sample: Int, tail: String)] = []
        for segment in asr.segments {
            guard segment.endSample > previousEnd, segment.endSample <= sampleCount else { return nil }
            previousEnd = segment.endSample
            prefix += segment.text
            let candidate = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard complete(candidate) else { continue }
            let tail = key(candidate).split(separator: " ").suffix(3).joined(separator: " ")
            observed.append((segment.endSample, tail))
            // Leading words and segment grouping can change with more context.
            // Confirm the sentence ending, rather than requiring every earlier word
            // to remain byte-identical. Timestamps stay relative to the same audio start.
            let stableEnd = previousSentenceEnds.contains { abs($0.sample - segment.endSample) <= 3_200 && $0.tail == tail }
            if quiet || (segment.endSample <= sampleCount - 16_000 &&
                         (key(previousTranscript).hasPrefix(key(candidate)) || stableEnd)) {
                selected = (candidate, segment.endSample)
            }
        }
        previousSentenceEnds = Array((previousSentenceEnds + observed).suffix(64))
        return selected
    }
    private func drain() async {
        defer { job = nil }
        while let request = pendingEnd, !cancelled, !suspended {
            let end = request.end
            pendingEnd = nil
            guard end > result.committedSamples else { continue }
            let start = ProcessInfo.processInfo.systemUptime
            defer { result.processingSeconds += ProcessInfo.processInfo.systemUptime - start }
            do {
                let audio = try await snapshot(result.committedSamples..<end)
                try check()
                trace("preview.asr.start.samples=\(audio.samples.count)")
                let asr = try await recognize(audio, result.source ?? requestedSource)
                try check(); result.asrSeconds += asr.processingSeconds
                let transcript = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let selected = completedPrefix(asr, sampleCount: end - result.committedSamples, quiet: request.quiet)
                trace("preview.asr.end.segments=\(asr.segments.count).selected=\(selected?.samples ?? 0).quiet=\(request.quiet)")
                previousTranscript = transcript
                guard let selected else { continue }
                let text = selected.text
                let source = result.source ?? requestedSource ?? asr.language
                let target = requestedTarget
                trace("preview.mt.start")
                let mt = source == target ? TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 0)
                    : try await translate(text, source, target)
                try check()
                let translated = mt.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { throw PipelineError.inference }
                result.source = source; result.target = target
                result.sourceText = [result.sourceText, text].filter { !$0.isEmpty }.joined(separator: " ")
                result.translatedText = [result.translatedText, translated].filter { !$0.isEmpty }.joined(separator: " ")
                result.committedSamples += selected.samples; previousTranscript = ""; previousSentenceEnds.removeAll(); result.mtSeconds += mt.processingSeconds; result.blocks += 1
                result.translations.append(RecordingPreviewBlock(source: text, translation: translated))
                publish(result)
                trace("preview.publish.blocks=\(result.blocks).samples=\(result.committedSamples)")
                // Prefer already queued recognition over optional speculative speech.
                if result.firstSpeech == nil, pendingEnd == nil, !suspended, let prepareSpeech {
                    do {
                        let prepared = try await prepareSpeech(result.translatedText, target)
                        try check(); result.firstSpeech = prepared
                    } catch is CancellationError { throw CancellationError() }
                    catch { /* A TTS failure must not discard a valid translation. */ }
                }
            } catch is CancellationError { return }
            catch { trace("preview.error"); result.fallbackReason = "preview-error"; suspended = true; pendingEnd = nil }
        }
    }
}
