import Foundation

public enum MMSSpeechText {
    public enum InputError: LocalizedError {
        case unsupportedCharacters, numbers
        public var errorDescription: String? {
            switch self {
            case .unsupportedCharacters: return L10n.text("Этот голос не поддерживает некоторые символы текста. Выберите другой голос или измените текст для озвучки.")
            case .numbers: return L10n.text("Этот голос пока не умеет читать эти числа. Напишите их словами для озвучки.")
            }
        }
    }
    public static func prepare(_ text: String, tokens: String, language: String) throws -> String {
        let supported = Set(tokens.split(separator: "\n").compactMap { line -> String? in
            guard let space = line.lastIndex(of: " ") else { return nil }
            return String(line[..<space])
        })
        var result = text.precomposedStringWithCanonicalMapping.lowercased()
        // ICU silently falls back to English for many small languages. Only these
        // language formatters were verified; never read that fallback as native speech.
        let numberLanguages: Set<String> = ["ta", "kn", "gu", "km", "my", "ky", "pa", "lo", "fo", "bn", "he", "mr"]
        let pattern = try NSRegularExpression(pattern: "[0-9]+(?:[.,][0-9]+)?")
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard numberLanguages.contains(language), let range = Range(match.range, in: result) else { throw InputError.numbers }
            let value = NSDecimalNumber(string: String(result[range]).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
            let formatter = NumberFormatter(); formatter.locale = Locale(identifier: language); formatter.numberStyle = .spellOut
            guard value != .notANumber, let words = formatter.string(from: value),
                  !words.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else { throw InputError.numbers }
            result.replaceSubrange(range, with: words.lowercased())
        }
        for scalar in result.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar), !supported.contains(String(scalar)) { throw InputError.numbers }
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                guard supported.contains(String(scalar)) else { throw InputError.unsupportedCharacters }
            }
        }
        return result
    }
}
