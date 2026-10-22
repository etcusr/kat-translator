import Foundation
import OfflineCore
private final class MLXTranslationFlag: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init() throws { guard let p = kat_mlx_flag_create() else { throw PipelineError.modelLoad }; pointer = p }
    private let lock = NSLock()
    private var cancelledValue = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledValue }
    func cancel() { lock.lock(); cancelledValue = true; lock.unlock(); kat_mlx_flag_cancel(pointer) }
    deinit { kat_mlx_flag_free(pointer) }
}
private final class MLXPartialReporter {
    let completed: String
    let report: @Sendable (String) -> Void
    let separator: String
    init(completed: String, separator: String = " ", report: @escaping @Sendable (String) -> Void) {
        self.completed = completed; self.separator = separator; self.report = report
    }
    func receive(_ text: String) { report(completed.isEmpty ? text : completed + separator + text) }
}
private enum MacGlossaryError: LocalizedError {
    case preparation
    var errorDescription: String? { L10n.text("Не удалось подготовить экспериментальный словарь. Отключите его в настройках и повторите перевод.") }
}
enum MacTranslationOptions {
    static func glossaryEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "macExperimentalTranslationGlossary") as? Bool ?? false
    }
    static func chunksEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "macExperimentalTranslationChunks") as? Bool ?? true
    }
}
final class MLXTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.translation", qos: .userInitiated)
    private var context: UnsafeMutableRawPointer?
    private var model: TranslationModel = .index9B
    private var glossaryDocument: (UUID, Bool)? // Accessed only on the serial engine queue.
    private let lock = NSLock()
    private var flag: MLXTranslationFlag?
    private let chunkingEnabled: @Sendable () -> Bool
    private let glossaryEnabled: @Sendable () -> Bool
    init(glossaryEnabled: @escaping @Sendable () -> Bool = { MacTranslationOptions.glossaryEnabled() }, chunkingEnabled: @escaping @Sendable () -> Bool = { MacTranslationOptions.chunksEnabled() }) {
        self.chunkingEnabled = chunkingEnabled; self.glossaryEnabled = glossaryEnabled
    }
    func load(modelURL: URL) async throws { try await load(modelURL: modelURL, model: .index9B) }
    func load(modelURL: URL, model: TranslationModel) async throws {
        guard model == .index9B else { throw PipelineError.modelLoad }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
            if let old = self.context { kat_mlx_free(old); self.context = nil }
            self.model = model; self.glossaryDocument = nil
            TranslationMemoryTrace.record("load.start", model: model)
            let start = ProcessInfo.processInfo.systemUptime
            guard let resources = Bundle.main.resourceURL else { c.resume(throwing: PipelineError.modelLoad); return }
            self.context = kat_mlx_load(resources.path, modelURL.path)
            TranslationMemoryTrace.record(self.context == nil ? "load.failed" : "load.complete", model: model, seconds: ProcessInfo.processInfo.systemUptime - start)
            if self.context == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
        } }
    }
    private func setFlag(_ flag: MLXTranslationFlag?) { lock.lock(); defer { lock.unlock() }; self.flag = flag }
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
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, document: TranslationDocument,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: progress, partial: Optional(partial), document: document)
    }
    private func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                           partial: (@Sendable (String) -> Void)?, document: TranslationDocument? = nil) async throws -> TranslationResult {
        try Task.checkCancellation()
        guard TranslationLanguage.details(source).connected(to: model), TranslationLanguage.details(target).connected(to: model) else { throw PipelineError.modelLanguageUnavailable }
        try TranslationPrompt.validate(text)
        let useSmallChunks = chunkingEnabled()
        let requestedGlossary = glossaryEnabled() && source == .russian && target == .english
        let sharedDocument = document
        let document = document ?? TranslationDocument(text: text)
        try TranslationPrompt.validate(document.text)
        let flag = try MLXTranslationFlag(); setFlag(flag); defer { setFlag(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in self.queue.async {
                do {
                    guard let context = self.context else { throw PipelineError.modelLoad }
                    let started = ProcessInfo.processInfo.systemUptime
                    // Keep the choice stable across a single image, but never enable it
                    // merely because a caller supplies document context.
                    if sharedDocument == nil || self.glossaryDocument?.0 != document.id {
                        self.glossaryDocument = (document.id, requestedGlossary)
                    }
                    let useGlossary = self.glossaryDocument?.1 == true && source == .russian && target == .english
                    if useGlossary { progress(TranslationWork(pieces: [text]).progress) }
                    let prepared = kat_mlx_prepare_glossary(context, useGlossary ? document.text : "", useGlossary ? document.id.uuidString : "", flag.pointer)
                    if prepared == 2 { throw CancellationError() }
                    guard prepared == 0 else { throw MacGlossaryError.preparation }
                    let planned = useSmallChunks
                        ? try TranslationChunks.plan(text, count: { Int(kat_mlx_count(context, "", $0, "")) }, cancelled: { flag.isCancelled }) : [text]
                    let pieces = try planned.flatMap { sourcePiece in try TextSegments.split(sourcePiece) { part in
                        let request = self.model.request(text: part.trimmingCharacters(in: .whitespacesAndNewlines), source: source, target: target)
                        let count = kat_mlx_count(context, request.prefix, request.text, request.suffix)
                        // The runtime can use all free response positions. Plan that space
                        // before generation; retain limit-hit retries for unusually long output.
                        guard count > 0 && count <= 1536 else { return false }
                        let sourceCount = kat_mlx_count(context, "", request.text, "")
                        return TranslationPreflight.fits(promptTokens: Int(count), sourceTokens: Int(sourceCount))
                    } }
                    var translated: [String] = []; var first: Double?
                    var completed = "", separator = " "
                    var work = TranslationWork(pieces: pieces)
                    progress(work.progress)
                    while let part = work.current {
                        let input = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if input.isEmpty { work.completeCurrent(); progress(work.progress); continue }
                        var output = [CChar](repeating: 0, count: 65_536); var tokenSeconds = -1.0
                        let callStart = ProcessInfo.processInfo.systemUptime
                        TranslationMemoryTrace.record("translate.start", model: self.model)
                        let request = self.model.request(text: input, source: source, target: target)
                        let done = completed
                        let code: Int32
                        if let partial {
                            let reporter = MLXPartialReporter(completed: done, separator: separator, report: partial)
                            code = withExtendedLifetime(reporter) {
                                kat_mlx_run_stream(context, request.prefix, request.text, request.suffix,
                                    flag.pointer, &output, output.count, &tokenSeconds, { text, user in
                                        guard let text, let user else { return }
                                        Unmanaged<MLXPartialReporter>.fromOpaque(user).takeUnretainedValue()
                                            .receive(String(cString: text))
                                    }, Unmanaged.passUnretained(reporter).toOpaque())
                            }
                        } else {
                            code = kat_mlx_run(context, request.prefix, request.text, request.suffix, flag.pointer, &output, output.count, &tokenSeconds)
                        }
                        TranslationMemoryTrace.record("translate.complete", model: self.model, seconds: ProcessInfo.processInfo.systemUptime - callStart, code: code)
                        if code == 2 { throw CancellationError() }
                        if code == 1 {
                            partial?(done)
                            try work.splitCurrent(); progress(work.progress); continue
                        }
                        guard code == 0 else { throw PipelineError.inference }
                        if first == nil && tokenSeconds >= 0 { first = callStart - started + tokenSeconds }
                        let result = String(cString: output).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !result.isEmpty else { throw PipelineError.inference }
                        completed = done.isEmpty ? result : done + separator + result
                        if useSmallChunks {
                            let whitespace = String(part.reversed().prefix(while: { $0.isWhitespace }).reversed())
                            separator = whitespace.contains("\n\n") ? "\n\n" : (whitespace.contains("\n") ? "\n" : " ")
                        }
                        translated.append(result); work.completeCurrent(); progress(work.progress)
                        if useSmallChunks { partial?(completed) }
                    }
                    guard !translated.isEmpty else { throw PipelineError.noSpeech }
                    continuation.resume(returning: TranslationResult(text: completed, firstTokenSeconds: first,
                        processingSeconds: ProcessInfo.processInfo.systemUptime - started, fragments: translated.count))
                } catch { continuation.resume(throwing: error) }
            } }
        } onCancel: { flag.cancel() }
    }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async { if let p = self.context { kat_mlx_free(p); self.context = nil; TranslationMemoryTrace.record("unload.complete", model: self.model) }; c.resume() } }
    }
    deinit { if let context { kat_mlx_free(context) } }
}
