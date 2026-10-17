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
    private static func indexBackend() -> any TranslationBackend { MLXTranslationBackend() }
    private static func opusBackend() -> any TranslationBackend { OpusGPUTranslationBackend() }
    #else
    private static func indexBackend() -> any TranslationBackend { LlamaTranslationBackend() }
    private static func opusBackend() -> any TranslationBackend { OpusTranslationBackend() }
    #endif
    init(llama: (any TranslationBackend)? = nil, opus: (any TranslationBackend)? = nil) {
        self.llama = llama ?? Self.indexBackend(); self.opus = opus ?? Self.opusBackend()
        #if os(macOS)
        compact = LlamaTranslationBackend()
        #else
        compact = self.llama
        #endif
        directions = OpusTranslationBackend()
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
    func cancel() { llama.cancel(); compact.cancel(); opus.cancel(); directions.cancel() }
    func unload() async { cancel(); await llama.unload(); await compact.unload(); await opus.unload(); await directions.unload() }
}
