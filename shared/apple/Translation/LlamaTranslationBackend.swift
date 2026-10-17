import Foundation
import OfflineCore
private final class TranslationFlag: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init() throws { guard let p = ot_mt_flag_create() else { throw PipelineError.modelLoad }; pointer = p }
    func cancel() { ot_mt_flag_cancel(pointer) }
    deinit { ot_mt_flag_free(pointer) }
}
/// Polls the running request's generated text off the translation queue; `stop()` drains the last poll.
private final class PartialWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.translation.partial", qos: .userInitiated)
    private let timer: DispatchSourceTimer
    private var last = ""
    init(context: UnsafeMutableRawPointer, report: @escaping @Sendable (String) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(60), repeating: .milliseconds(60))
        timer.setEventHandler { [unowned self] in
            var buffer = [CChar](repeating: 0, count: 16_384)
            let length = ot_mt_partial(context, &buffer, buffer.count)
            guard length > 0, length < buffer.count else { return }
            let text = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != self.last else { return }
            self.last = text; report(text)
        }
        timer.resume()
    }
    func stop() { timer.cancel(); queue.sync {} }
}
final class LlamaTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.translation", qos: .userInitiated)
    private var context: UnsafeMutableRawPointer?
    private var model: TranslationModel = .index9B
    private let lock = NSLock()
    private var flag: TranslationFlag?
    func load(modelURL: URL) async throws { try await load(modelURL: modelURL, model: .index9B) }
    func load(modelURL: URL, model: TranslationModel) async throws {
        guard model == .index9B || model == .index2B else { throw PipelineError.modelLoad }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
            if let old = self.context { ot_mt_free(old); self.context = nil }
            self.model = model
            TranslationMemoryTrace.record("load.start", model: model)
            let start = ProcessInfo.processInfo.systemUptime
            self.context = ot_mt_load(modelURL.path)
            TranslationMemoryTrace.record(self.context == nil ? "load.failed" : "load.complete", model: model, seconds: ProcessInfo.processInfo.systemUptime - start)
            if self.context == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
        } }
    }
    private func setFlag(_ flag: TranslationFlag?) { lock.lock(); defer { lock.unlock() }; self.flag = flag }
    func cancel() { lock.lock(); defer { lock.unlock() }; flag?.cancel() }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: { _ in })
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: progress, partial: nil)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: progress, partial: Optional(partial))
    }
    private func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                           partial: (@Sendable (String) -> Void)?) async throws -> TranslationResult {
        try Task.checkCancellation()
        guard TranslationLanguage.details(source).connected(to: model), TranslationLanguage.details(target).connected(to: model) else { throw PipelineError.modelLanguageUnavailable }
        try TranslationPrompt.validate(text)
        let flag = try TranslationFlag(); setFlag(flag); defer { setFlag(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in self.queue.async {
                do {
                    guard let context = self.context else { throw PipelineError.modelLoad }
                    let started = ProcessInfo.processInfo.systemUptime
                    let pieces = try TextSegments.split(text) { part in
                        let request = self.model.request(text: part.trimmingCharacters(in: .whitespacesAndNewlines), source: source, target: target)
                        let count = ot_mt_count(context, request.prefix, request.text, request.suffix)
                        // The runtime can use all free response positions. Plan that space
                        // before generation; retain limit-hit retries for unusually long output.
                        guard count > 0 && count <= 1536 else { return false }
                        let sourceCount = ot_mt_count(context, "", request.text, "")
                        return TranslationPreflight.fits(promptTokens: Int(count), sourceTokens: Int(sourceCount))
                    }
                    var translated: [String] = []; var first: Double?
                    var work = TranslationWork(pieces: pieces)
                    progress(work.progress)
                    while let part = work.current {
                        let input = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if input.isEmpty { work.completeCurrent(); progress(work.progress); continue }
                        var output = [CChar](repeating: 0, count: 65_536); var tokenSeconds = -1.0
                        let callStart = ProcessInfo.processInfo.systemUptime
                        TranslationMemoryTrace.record("translate.start", model: self.model)
                        let request = self.model.request(text: input, source: source, target: target)
                        let done = translated.joined(separator: " ")
                        let watcher = partial.map { report in PartialWatcher(context: context) { report(done.isEmpty ? $0 : done + " " + $0) } }
                        let code = ot_mt_run(context, request.prefix, request.text, request.suffix, flag.pointer, &output, output.count, &tokenSeconds)
                        watcher?.stop()
                        TranslationMemoryTrace.record("translate.complete", model: self.model, seconds: ProcessInfo.processInfo.systemUptime - callStart, code: code)
                        if code == 2 { throw CancellationError() }
                        if code == 1 {
                            try work.splitCurrent(); progress(work.progress); continue
                        }
                        guard code == 0 else { throw PipelineError.inference }
                        if first == nil && tokenSeconds >= 0 { first = callStart - started + tokenSeconds }
                        let result = String(cString: output).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !result.isEmpty else { throw PipelineError.inference }
                        translated.append(result); work.completeCurrent(); progress(work.progress)
                    }
                    guard !translated.isEmpty else { throw PipelineError.noSpeech }
                    continuation.resume(returning: TranslationResult(text: translated.joined(separator: " "), firstTokenSeconds: first,
                        processingSeconds: ProcessInfo.processInfo.systemUptime - started, fragments: translated.count))
                } catch { continuation.resume(throwing: error) }
            } }
        } onCancel: { flag.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async { if let p = self.context { ot_mt_free(p); self.context = nil; TranslationMemoryTrace.record("unload.complete", model: self.model) }; c.resume() } }
    }
    deinit { if let context { ot_mt_free(context) } }
}
