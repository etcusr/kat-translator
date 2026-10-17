import Foundation
public extension SpeechLanguage {
    var opposite: SpeechLanguage { self == .russian ? .english : .russian }
    // Legacy default used only to decode RU/EN history and by old callers.

}
public struct TranslationResult: Sendable {
    public let text: String
    public let firstTokenSeconds: Double?
    public let processingSeconds: Double
    public let fragments: Int
    public init(text: String, firstTokenSeconds: Double?, processingSeconds: Double, fragments: Int) {
        self.text = text; self.firstTokenSeconds = firstTokenSeconds; self.processingSeconds = processingSeconds; self.fragments = fragments
    }
}
public struct SpeechPCM: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public init(samples: [Float], sampleRate: Int) { self.samples = samples; self.sampleRate = sampleRate }
}
public protocol TranslationBackend: AnyObject, Sendable {
    func load(modelURL: URL) async throws
    func load(modelURL: URL, model: TranslationModel) async throws
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult
    /// `partial` receives the translation generated so far; the returned result stays authoritative.
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult
    func cancel()
    func unload() async
}
public extension TranslationBackend {
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        progress(TranslationWork(pieces: [text]).progress)
        return try await translate(text: text, source: source, target: target)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: progress)
    }
    func load(modelURL: URL, model: TranslationModel) async throws { try await load(modelURL: modelURL) }
}
public protocol SpeechSynthesisBackend: AnyObject, Sendable {
    func load(directory: URL, language: SpeechLanguage) async throws
    func synthesize(text: String) async throws -> SpeechPCM
    func cancel()
    func unload() async
}
public enum PipelineError: LocalizedError {
    case recognitionUnavailable, modelLanguageUnavailable, modelLoad, inference, tooLong, noSpeech, cancelled, invalidAudio, unsupportedText, unsupportedLanguage, textNeedsLanguage, voiceUnavailable
    public var errorDescription: String? {
        switch self {
        case .recognitionUnavailable: return L10n.text("Голосовой ввод этого языка пока недоступен. Используйте текстовый режим.")
        case .modelLanguageUnavailable: return L10n.text("Эта пара языков не подключена для выбранной модели. Выберите другую модель или языки.")
        case .modelLoad: return L10n.text("Не удалось загрузить модель. Попробуйте режим экономии памяти в настройках.")
        case .inference: return L10n.text("Не удалось обработать фрагмент. Попробуйте более короткую реплику.")
        case .tooLong: return L10n.text("Фрагмент слишком длинный для модели. Перевод не был обрезан — разделите реплику.")
        case .noSpeech: return L10n.text("Речь не обнаружена. Попробуйте снова.")
        case .cancelled: return L10n.text("Обработка отменена.")
        case .unsupportedText: return L10n.text("Текст содержит недопустимый нулевой символ. Удалите его и повторите перевод.")
        case .unsupportedLanguage: return L10n.text("Не удалось определить язык. Повторите фразу или выберите исходный язык вручную.")
        case .voiceUnavailable: return L10n.text("Скачайте голос для этого языка в настройках. Текстовый перевод доступен.")
        case .textNeedsLanguage: return L10n.text("Не удалось определить язык текста. Добавьте больше текста или выберите исходный язык вручную.")
        case .invalidAudio: return L10n.text("Не удалось создать звук.")
        }
    }
}
