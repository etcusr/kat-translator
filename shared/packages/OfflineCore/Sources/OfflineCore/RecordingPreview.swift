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
    private var recognitionStart = 0
    private var contextText = ""
    private var usesTimestamps = false
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
    public func finish(end: Int? = nil, speechEnd: Int? = nil) async -> RecordingPreviewResult {
        closed = true
        await job?.value
        // Complete only the still-unpublished tail with its retained audio context.
        // This does not retranslate or replace already committed blocks.
        if let end, usesTimestamps, !cancelled, !suspended,
           (speechEnd ?? end) > result.committedSamples, end > result.committedSamples {
            await process(end: end, quiet: true, final: true)
        }
        return result
    }
    private func check() throws { try Task.checkCancellation(); if cancelled { throw CancellationError() } }
    private func words(_ value: String) -> [(key: String, range: Range<String.Index>)] {
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+")
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            guard let range = Range($0.range, in: value) else { return nil }
            return (String(value[range]).lowercased(), range)
        }
    }
    private func key(_ value: String) -> [String] { words(value).map(\.key) }
    private func complete(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.hasSuffix("..."), !value.hasSuffix("…") else { return false }
        return value.last.map { ".!?。！？".contains($0) } ?? false
    }
    private func unpublished(_ text: String) -> String? {
        guard !contextText.isEmpty else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let context = key(contextText), tokens = words(text), current = tokens.map(\.key)
        var offset = context.count
        if !current.starts(with: context) {
            // Align only ALREADY committed context. Require a stable three-word
            // anchor and a unique low-edit-cost prefix; never fuzz-match new words.
            guard context.count >= 5 else { return nil }
            let limit = min(current.count, context.count + 5)
            guard limit >= 3 else { return nil }
            var costs = Array(0...limit)
            for (i, word) in context.enumerated() {
                var next = Array(repeating: 0, count: limit + 1); next[0] = i + 1
                for j in 1...limit {
                    next[j] = min(costs[j] + 1, next[j - 1] + 1, costs[j - 1] + (word == current[j - 1] ? 0 : 1))
                }
                costs = next
            }
            let lower = max(3, context.count - 5)
            guard lower <= limit else { return nil }
            let candidates = (lower...limit).filter {
                Array(current.prefix($0).suffix(3)) == Array(context.suffix(3)) && costs[$0] <= max(1, context.count / 5)
            }
            guard let minimum = candidates.map({ costs[$0] }).min() else { return nil }
            let best = candidates.filter { costs[$0] == minimum }
            guard best.count == 1, let match = best.first else { return nil }
            offset = match
        }
        guard tokens.count > offset else { return "" }
        return String(text[tokens[offset].range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func completedPrefix(_ asr: ASRResult, sampleCount: Int, quiet: Bool, final: Bool) -> (full: String, text: String, samples: Int)? {
        let text = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asr.segments.isEmpty else {
            guard contextText.isEmpty, quiet && complete(text) else { return nil }
            return (text, text, sampleCount)
        }
        usesTimestamps = true
        guard key(asr.segments.map(\.text).joined()) == key(text) else { return nil }
        var prefix = "", previousEnd = 0
        var selected: (full: String, text: String, samples: Int)?
        for segment in asr.segments {
            guard segment.endSample > previousEnd, segment.endSample <= sampleCount else { return nil }
            previousEnd = segment.endSample; prefix += segment.text
            let candidate = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard recognitionStart + segment.endSample > result.committedSamples,
                  complete(candidate), let fresh = unpublished(candidate), !fresh.isEmpty else { continue }
            // LocalAgreement: every word of the prefix must agree across consecutive
            // hypotheses. A pause or a matching last few words cannot override this.
            if let previous = unpublished(previousTranscript), key(previous).starts(with: key(fresh)),
               quiet || segment.endSample <= sampleCount - 16_000 {
                selected = (candidate, fresh, segment.endSample)
            }
        }
        if final, let fresh = unpublished(text), !fresh.isEmpty {
            return (text, fresh, sampleCount)
        }
        return selected
    }
    private func trimContext(asr: ASRResult, selectedEnd: Int, full: String, offeredEnd: Int) {
        contextText = full
        guard offeredEnd - recognitionStart > 30 * 16_000 else { return }
        // Trim at an older confirmed sentence, retaining at least the last one.
        let candidates = asr.segments.filter { recognitionStart + $0.endSample < selectedEnd && complete($0.text) }
        guard let cut = candidates.last else { return }
        let removed = asr.segments.prefix { $0.endSample <= cut.endSample }.map(\.text).joined()
        let tokens = words(full), count = key(removed).count
        guard count < tokens.count else { return }
        contextText = String(full[tokens[count].range.lowerBound...])
        recognitionStart += cut.endSample
        previousTranscript = ""
    }
    private func drain() async {
        defer { job = nil }
        while let request = pendingEnd, !cancelled, !suspended {
            let end = request.end
            pendingEnd = nil
            guard end > result.committedSamples else { continue }
            await process(end: end, quiet: request.quiet, final: false)
        }
    }
    private func process(end: Int, quiet: Bool, final: Bool) async {
        let start = ProcessInfo.processInfo.systemUptime
        defer { result.processingSeconds += ProcessInfo.processInfo.systemUptime - start }
        do {
            let audio = try await snapshot(recognitionStart..<end)
            try check()
            trace("preview.asr.start.samples=\(audio.samples.count)")
            let asr = try await recognize(audio, result.source ?? requestedSource)
            try check(); result.asrSeconds += asr.processingSeconds
            let transcript = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let selected = completedPrefix(asr, sampleCount: end - recognitionStart, quiet: quiet, final: final)
            trace("preview.asr.end.segments=\(asr.segments.count).selected=\(selected?.samples ?? 0).quiet=\(quiet)")
            previousTranscript = transcript
            guard let selected else {
                if final, !contextText.isEmpty, unpublished(transcript) == "" {
                    // The context-aware final pass heard no new words. Do not
                    // send the trailing VAD hangover to a second, contextless ASR.
                    result.committedSamples = end
                }
                return
            }
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
            result.committedSamples = recognitionStart + selected.samples
            if usesTimestamps { trimContext(asr: asr, selectedEnd: result.committedSamples, full: selected.full, offeredEnd: end) }
            else { recognitionStart = result.committedSamples; previousTranscript = "" }
            result.mtSeconds += mt.processingSeconds; result.blocks += 1
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
