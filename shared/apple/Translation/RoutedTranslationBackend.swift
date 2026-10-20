import Foundation
import OfflineCore

/// Model choice selects one engine; switching always releases every native context first.
/// Index 9B uses MLX on Mac and GGUF/Metal on iPhone; Index 2B is GGUF/Metal on both.
/// OPUS: the English package (GPU worker on Mac, CTranslate2 on iPhone) and the direction
/// packages (CTranslate2 on both).
final class RoutedTranslationBackend: TranslationBackend, @unchecked Sendable {
    private let llama: any TranslationBackend
    private let compact: any TranslationBackend
    private let opus: any TranslationBackend
    private let directions: any TranslationBackend
    private let lock = NSLock()
    private var model: TranslationModel = .index9B
    #if os(macOS)
    private var residencyObserver: NSObjectProtocol?
    private static var idleSeconds: Double {
        let saved = UserDefaults.standard.object(forKey: "macTranslationIdleMinutes") as? Double ?? 5
        return (saved.isFinite ? min(60, max(1, saved)) : 5) * 60
    }
    #endif
    #if os(macOS)
    private static func indexBackend() -> any TranslationBackend { MLXTranslationBackend() }
    private static func opusBackend() -> any TranslationBackend { OpusGPUTranslationBackend() }
    #else
    private static func indexBackend() -> any TranslationBackend { LlamaTranslationBackend() }
    private static func opusBackend() -> any TranslationBackend { OpusTranslationBackend() }
    #endif
    init(llama: (any TranslationBackend)? = nil, opus: (any TranslationBackend)? = nil) {
        #if os(macOS)
        self.llama = RetainedTranslationBackend(base: llama ?? Self.indexBackend(), idleSeconds: Self.idleSeconds)
        self.opus = RetainedTranslationBackend(base: opus ?? Self.opusBackend(), idleSeconds: Self.idleSeconds)
        compact = RetainedTranslationBackend(base: LlamaTranslationBackend(), idleSeconds: Self.idleSeconds)
        directions = RetainedTranslationBackend(base: OpusTranslationBackend(), idleSeconds: Self.idleSeconds)
        residencyObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            let seconds = Self.idleSeconds
            Task { for backend in [self.llama, self.compact, self.opus, self.directions] {
                await (backend as? RetainedTranslationBackend)?.setIdleTimeout(seconds)
            } }
        }
        #else
        self.llama = llama ?? Self.indexBackend(); self.opus = opus ?? Self.opusBackend()
        compact = self.llama
        directions = OpusTranslationBackend()
        #endif
    }
    deinit {
        #if os(macOS)
        if let residencyObserver { NotificationCenter.default.removeObserver(residencyObserver) }
        #endif
    }

    private var active: any TranslationBackend {
        lock.lock(); defer { lock.unlock() }
        switch model {
        case .opusBig: return opus
        case .opusDirections: return directions
        case .index2B: return compact
        default: return llama
        }
    }
    private func select(_ value: TranslationModel) { lock.lock(); defer { lock.unlock() }; model = value }
    func load(modelURL: URL) async throws { try await load(modelURL: modelURL, model: .index9B) }
    func load(modelURL: URL, model: TranslationModel) async throws {
        await unload()
        select(model)
        try await active.load(modelURL: modelURL, model: model)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await active.translate(text: text, source: source, target: target)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage,
                   progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        try await active.translate(text: text, source: source, target: target, progress: progress)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await active.translate(text: text, source: source, target: target, progress: progress, partial: partial)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, document: TranslationDocument,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await active.translate(text: text, source: source, target: target, document: document, progress: progress, partial: partial)
    }
    func cancel() { llama.cancel(); compact.cancel(); opus.cancel(); directions.cancel() }
    func unload() async { cancel(); await llama.unload(); await compact.unload(); await opus.unload(); await directions.unload() }
}
