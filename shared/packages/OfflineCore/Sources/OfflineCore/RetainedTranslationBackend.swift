import Foundation

/// Retain weights between requests, release them while idle, and transparently reload.
/// Explicit unload forgets the selection. A serial lease prevents idle expiry, model
/// switching and concurrent callers from freeing an engine while it is in use.
public final class RetainedTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let base: any TranslationBackend
    private let state: State
    public init(base: any TranslationBackend, idleSeconds: Double = 300) {
        self.base = base; state = State(base: base, idleSeconds: idleSeconds)
    }
    public func setIdleTimeout(_ seconds: Double) async { await state.configure(seconds) }
    public func load(modelURL: URL) async throws { try await load(modelURL: modelURL, model: .index9B) }
    public func load(modelURL: URL, model: TranslationModel) async throws { try await state.load(modelURL, model) }
    public func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: { _ in })
    }
    public func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        try await state.translate(text, source, target, progress, nil)
    }
    public func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                          partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await state.translate(text, source, target, progress, partial)
    }
    public func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, document: TranslationDocument,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await state.translate(text, source, target, progress, partial, document: document)
    }
    public func cancel() { base.cancel() }
    public func unload() async { base.cancel(); await state.unload() }

    private actor State {
        let base: any TranslationBackend
        var selected: (URL, TranslationModel)?
        var loaded = false, busy = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var timer: Task<Void, Never>?
        var epoch = 0
        var seconds: Double
        init(base: any TranslationBackend, idleSeconds: Double) {
            self.base = base; seconds = Self.valid(idleSeconds)
        }
        static func valid(_ value: Double) -> Double { value.isFinite && value > 0 ? min(3600, value) : 300 }
        func stopTimer() { epoch += 1; timer?.cancel(); timer = nil }
        func schedule() {
            stopTimer()
            guard loaded, !busy else { return }
            let ticket = epoch, delay = seconds
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
                await self?.expire(ticket)
            }
        }
        func configure(_ value: Double) {
            let value = Self.valid(value)
            guard value != seconds else { return }
            seconds = value; schedule()
        }
        func acquire() async {
            if busy { await withCheckedContinuation { waiters.append($0) } }
            else { busy = true }
            stopTimer()
        }
        func release() {
            if !waiters.isEmpty { waiters.removeFirst().resume() }
            else { busy = false; schedule() }
        }
        func expire(_ ticket: Int) async {
            // No await between checking and taking the lease.
            guard ticket == epoch, !busy, loaded else { return }
            busy = true; stopTimer()
            await base.unload(); loaded = false
            release()
        }
        func load(_ url: URL, _ model: TranslationModel) async throws {
            await acquire(); defer { release() }
            try Task.checkCancellation()
            if let selected, selected.0 == url, selected.1 == model, loaded { return }
            if loaded { await base.unload(); loaded = false }
            selected = nil
            do { try await base.load(modelURL: url, model: model) }
            catch { await base.unload(); throw error }
            selected = (url, model); loaded = true
        }
        func translate(_ text: String, _ source: SpeechLanguage, _ target: SpeechLanguage,
                       _ progress: @escaping @Sendable (TranslationProgress) -> Void,
                       _ partial: (@Sendable (String) -> Void)?, document: TranslationDocument? = nil) async throws -> TranslationResult {
            await acquire(); defer { release() }
            try Task.checkCancellation()
            guard let selected else { throw PipelineError.modelLoad }
            return try await withTaskCancellationHandler {
                if !loaded {
                    do { try await base.load(modelURL: selected.0, model: selected.1); loaded = true }
                    catch { await base.unload(); throw error }
                }
                try Task.checkCancellation()
                if let document {
                    return try await base.translate(text: text, source: source, target: target, document: document, progress: progress, partial: partial ?? { _ in })
                }
                if let partial { return try await base.translate(text: text, source: source, target: target, progress: progress, partial: partial) }
                return try await base.translate(text: text, source: source, target: target, progress: progress)
            } onCancel: { base.cancel() }
        }
        func unload() async {
            await acquire(); defer { release() }
            await base.unload(); loaded = false; selected = nil
        }
        deinit { timer?.cancel() }
    }
}
