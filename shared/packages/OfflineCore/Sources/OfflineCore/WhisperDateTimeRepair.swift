import Foundation

/// A dotted or hyphenated triple followed by a Russian month can hide time + day-of-month.
/// Never infer its meaning from digits alone: require a second acoustic decoding
/// with spelled numbers, an ordinal day, and agreement on all surrounding words.
public enum WhisperDateTimeRepair {
    private static let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                 "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    private static let days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    private static let pattern = try! NSRegularExpression(pattern:
        "(?<![\\p{L}\\p{N}.,:-])([0-9]{1,2})[.-]([0-9]{1,2})[.-]([0-9]{1,2})[ \\t]+(" + months.joined(separator: "|") + ")(?!\\p{L})", options: [.caseInsensitive])
    private static let punctuationLoop = try! NSRegularExpression(pattern: "(?:[.!?,;:][ \\t]*){3,}")
    private struct Candidate {
        let range: Range<String.Index>
        let hour: Int
        let minute: Int
        let day: Int
        let month: String
    }

    public static func needsRetry(_ text: String, language: SpeechLanguage) -> Bool {
        language == .russian && candidate(text) != nil
    }

    public static func repair(_ original: String, retry: String) -> String {
        guard let c = candidate(original), retry.count <= original.count * 3 + 80,
              punctuationLoop.firstMatch(in: retry, range: NSRange(retry.startIndex..., in: retry)) == nil else { return original }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru"); formatter.numberStyle = .spellOut
        guard let hour = formatter.string(from: NSNumber(value: c.hour)),
              let minute = formatter.string(from: NSNumber(value: c.minute)) else { return original }
        let ordinal = RussianSpeechText.expandOrdinals("\(c.day)-го")
        let minutes = c.minute < 10 ? [minute, "ноль " + minute] : [minute]
        let expected = minutes.map { value in
            original.replacingCharacters(in: c.range, with: "\(hour) \(value) \(ordinal) \(c.month)")
        }
        // Punctuation may vary; words and their order may not. This also rejects
        // altered/unrelated numbers elsewhere in the second decoding.
        guard expected.contains(where: { words($0) == words(retry) }) else { return original }
        let timeAndDate = "\(c.hour):\(String(format: "%02d", c.minute)), \(c.day) \(c.month)"
        return original.replacingCharacters(in: c.range, with: timeAndDate)
    }

    private static func candidate(_ text: String) -> Candidate? {
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let match = matches.first,
              let range = Range(match.range, in: text) else { return nil }
        func part(_ n: Int) -> String { String(text[Range(match.range(at: n), in: text)!]) }
        guard let hour = Int(part(1)), let minute = Int(part(2)), let day = Int(part(3)),
              hour < 24, minute < 60, day > 0,
              let monthIndex = months.firstIndex(of: part(4).lowercased()), day <= days[monthIndex] else { return nil }
        let prefix = String(text[..<range.lowerBound])
        let identifierWords: Set<String> = ["код", "версия", "номер", "артикул", "сборка", "идентификатор", "ip"]
        if let previous = words(prefix).last, identifierWords.contains(previous) { return nil }
        return Candidate(range: range, hour: hour, minute: minute, day: day, month: part(4))
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
