import Foundation
public enum TranslationPrompt {
    public static func validate(_ text: String) throws {
        guard !text.utf8.contains(0) else { throw PipelineError.unsupportedText }
    }
    public static func prefix(source: SpeechLanguage, target: SpeechLanguage) -> String {
        let s = source.englishName; let t = target.englishName
        return "<bos><start_of_turn>user\nYou are a professional \(s) (\(source.rawValue)) to \(t) (\(target.rawValue)) translator. Your goal is to accurately convey the meaning and nuances of the original \(s) text while adhering to \(t) grammar, vocabulary, and cultural sensitivities.\nProduce only the \(t) translation, without any additional explanations or commentary. Please translate the following \(s) text into \(t):\n\n\n"
    }
    public static let suffix = "<end_of_turn>\n<start_of_turn>model\n"
}
