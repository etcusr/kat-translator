import Foundation
import NaturalLanguage
import LanguageIdentificationRuntime
public enum TextLanguageDetection {
    public static var attribution: String {
        guard let url = Bundle.module.url(forResource: "LanguageIdentification-NOTICE", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    /// Bundled, offline identification. Apple resolves close alternatives,
    /// but cannot override a confident fastText result (notably Belarusian versus Kazakh).
    public static func detect(_ text: String) -> SpeechLanguage? {
        let sample = String(text.prefix(4_000)).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard sample.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2,
              let url = Bundle.module.url(forResource: "lid.176", withExtension: "ftz") else { return nil }
        var prediction = KatLanguagePrediction()
        _ = kat_language_detect(url.path, sample, &prediction)
        let primary = withUnsafeBytes(of: prediction.language) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let alternative = withUnsafeBytes(of: prediction.alternative) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        func mapped(_ code: String) -> SpeechLanguage? {
            switch code {
            case "zh", "zh-Hans", "zh-Hant": return .chinese
            case "nb": return .lang_no
            default: return SpeechLanguage(rawValue: code)
            }
        }
        if prediction.confidence >= 0.6, prediction.confidence - prediction.alternativeConfidence >= 0.15 {
            return mapped(primary)
        }
        let apple = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        // A single greeting has low absolute scores across 176 languages even
        // when both detectors agree. Retry short input without incidental case
        // or edge punctuation; require agreement and a clear fastText margin.
        // This does not guess between shared words such as "gift" or "chat".
        let wordCount = sample.split(separator: " ").count
        if sample.count <= 40, wordCount <= 4 {
            let normalized = sample.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            var short = KatLanguagePrediction()
            if kat_language_detect(url.path, normalized, &short) != 0,
               short.confidence >= 0.35, short.confidence - short.alternativeConfidence >= 0.20 {
                let code = withUnsafeBytes(of: short.language) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if let best = apple.first, let language = mapped(code), language == mapped(best.key.rawValue) { return language }
            }
        }
        guard let best = apple.first, best.value >= 0.8,
              best.value - (apple.dropFirst().first?.value ?? 0) >= 0.2,
              let language = mapped(best.key.rawValue),
              language == mapped(primary) || language == mapped(alternative) else { return nil }
        return language
    }
}
