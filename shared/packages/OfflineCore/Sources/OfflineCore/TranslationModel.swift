import Foundation

public enum TranslationModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case opusBig = "opus-mt-big-en-zle-int8"
    case gemma4B = "translategemma-4b-q4km"
    case index9B = "index-translate-9b-q4km"
    case index2B = "index-translate-2b-q4km"
    /// Installed OPUS-MT Big direction packages; the pair selects the package (see OpusDirectionRoutes).
    case opusDirections = "opus-tc-big-directions"
    case qwen9B = "qwen35-9b-q4km"
    case mil4B = "mil-mmt46-4b-v1-q4km"
    case mil12B = "mil-mmt46-12b-v1-q4km"
    public static func restoredSelection(_ rawValue: String?) -> Self {
        let model = Self(rawValue: rawValue ?? "") ?? .index9B
        return selectable.contains(model) ? model : .index9B
    }
    // Keep retired IDs decodable for existing history and benchmark exports.
    public static var selectable: [Self] { [.opusBig, .opusDirections, .index2B, .index9B] }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .opusBig:
            #if os(macOS)
            return "OPUS Big · GPU"
            #else
            return "OPUS Big"
            #endif
        case .gemma4B: return "TranslateGemma 4B"
        case .index9B:
            #if os(macOS)
            return "Index-Translate 9B · MLX + MTP2"
            #elseif os(iOS)
            return "Index-Translate 9B · MTP2"
            #else
            return "Index-Translate 9B"
            #endif
        case .index2B: return "Index-Translate 2B"
        case .opusDirections: return "OPUS Big · " + L10n.text("направления")
        case .qwen9B: return "Qwen3.5 9B"
        case .mil4B: return "MiLMMT-46 4B"
        case .mil12B: return "MiLMMT-46 12B"
        }
    }
    public func supports(source: SpeechLanguage, target: SpeechLanguage) -> Bool {
        guard TranslationLanguage.details(source).connected(to: self), TranslationLanguage.details(target).connected(to: self) else { return false }
        if self == .opusDirections { return source == target || OpusDirectionRoutes.route(source.rawValue, target.rawValue) != nil }
        return self != .opusBig || source == target || source == .english || target == .english
    }
    public var defersRecognitionLoading: Bool { self == .index9B || self == .qwen9B || self == .mil12B }
    public var requiresGemmaTerms: Bool { self == .gemma4B || usesRawCompletion }
    private var usesRawCompletion: Bool { self == .mil4B || self == .mil12B }
    public var revision: String {
        switch self {
        case .opusBig:
            #if os(macOS)
            return "708be1d372fe4c358a352f404e6dc9ca0126ba48 / 09a40f722d6d8b76aaad6fe51a06c914622a13d1"
            #else
            return "366ea5f4bd2bc417a7430006408a0c6cd72a9f91"
            #endif
        case .gemma4B: return "35a7486e128b19642cdc72d7b91b21ba388aaf42"
        case .index9B:
            #if os(macOS)
            return "60fdfb05568b8a370cf0d95b0959fd8ac9877533"
            #else
            return "d01404384ba429b93f5f63d43573812d103b5bcd"
            #endif
        case .index2B: return "3a0eca6ce931d88d00614d427ab3ed8ff0743902"
        case .opusDirections: return "opus-mt-tc-big (Helsinki-NLP), CTranslate2 INT8"
        case .qwen9B: return "3885219b6810b007914f3a7950a8d1b469d598a5"
        case .mil4B: return "765aa350dc9aa28c41e2a9e34e1b25d56c0d3911"
        case .mil12B: return "d19a3282cf4dc9e629023795449469efd92fa5b5"
        }
    }
    public var modelCardURL: URL {
        let path: String
        switch self {
        case .opusBig: path = "Helsinki-NLP/opus-mt-tc-big-en-zle"
        case .gemma4B: path = "google/translategemma-4b-it"
        case .index9B:
            #if os(macOS)
            path = "rariruluis/Index-Translate-9B-MLX-4bit-MTP"
            #else
            path = "IndexTeam/Index-Translate-9B"
            #endif
        case .index2B: path = "IndexTeam/Index-Translate-2B"
        case .opusDirections: path = "Helsinki-NLP"
        case .qwen9B: path = "Qwen/Qwen3.5-9B"
        case .mil4B: path = "xiaomi-research/MiLMMT-46-4B-v1.0"
        case .mil12B: path = "xiaomi-research/MiLMMT-46-12B-v1.0"
        }
        return URL(string: "https://huggingface.co/" + path)!
    }
    // MiL's whole completion is literal content: no BOS/control parsing or split token boundary.
    public func request(text: String, source: SpeechLanguage, target: SpeechLanguage) -> (prefix: String, text: String, suffix: String) {
        let prefix = prefix(source: source, target: target)
        if usesRawCompletion { return ("", prefix + text + "\n" + milName(target) + ":", "") }
        return (prefix, text, suffix)
    }
    public func prefix(source: SpeechLanguage, target: SpeechLanguage) -> String {
        if self == .gemma4B { return TranslationPrompt.prefix(source: source, target: target) }
        if self == .qwen9B {
            return "<|im_start|>user\nTranslate the following text from \(source.englishName) into \(target.englishName). Output only the translation, without explanations.\n\n"
        }
        if usesRawCompletion {
            return "Translate this from \(milName(source)) to \(milName(target)):\n\(milName(source)): "
        }
        let name = TranslationLanguage.details(target).indexName ?? target.englishName
        return "<|im_start|>user\n请将以下文本翻译为\(name)，直接输出翻译结果，不要进行任何解释。\n\n"
    }
    private func milName(_ language: SpeechLanguage) -> String {
        if language == .chinese { return "Chinese (Simplified)" }
        if language.rawValue == "tl" { return "Tagalog" }
        if language.rawValue == "no" { return "Norwegian" }
        return language.englishName
    }
    public var suffix: String {
        if usesRawCompletion { return "" }
        return self == .gemma4B ? TranslationPrompt.suffix : "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
}
