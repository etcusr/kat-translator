import Foundation

/// Russian speech text: ordinals written with a hyphenated ending ("16-е", "15-го", "2026-м")
/// are spelled out before synthesis; voices otherwise read the digits and the ending separately.
public enum RussianSpeechText {
    private enum Form { case masculine, genitive, dative, prepositional, instrumental, neuter, feminine, feminineAccusative, pluralGenitive, pluralInstrumental }
    private static let endings: [(String, Form)] = [
        ("ыми", .pluralInstrumental), ("ими", .pluralInstrumental), ("ми", .pluralInstrumental),
        ("ого", .genitive), ("его", .genitive), ("го", .genitive),
        ("ому", .dative), ("ему", .dative), ("му", .dative),
        ("ый", .masculine), ("ий", .masculine), ("ой", .masculine), ("й", .masculine),
        ("ым", .instrumental), ("им", .instrumental), ("ом", .prepositional), ("ем", .prepositional), ("м", .prepositional),
        ("ое", .neuter), ("ее", .neuter), ("е", .neuter),
        ("ая", .feminine), ("яя", .feminine), ("я", .feminine),
        ("ую", .feminineAccusative), ("юю", .feminineAccusative), ("ю", .feminineAccusative),
        ("ых", .pluralGenitive), ("их", .pluralGenitive), ("х", .pluralGenitive)
    ]
    private static let stems: [Int: String] = [
        1: "перв", 2: "втор", 3: "трет", 4: "четвёрт", 5: "пят", 6: "шест", 7: "седьм", 8: "восьм", 9: "девят",
        10: "десят", 11: "одиннадцат", 12: "двенадцат", 13: "тринадцат", 14: "четырнадцат", 15: "пятнадцат",
        16: "шестнадцат", 17: "семнадцат", 18: "восемнадцат", 19: "девятнадцат", 20: "двадцат", 30: "тридцат",
        40: "сороков", 50: "пятидесят", 60: "шестидесят", 70: "семидесят", 80: "восьмидесят", 90: "девяност",
        100: "сот", 200: "двухсот", 300: "трёхсот", 400: "четырёхсот", 500: "пятисот", 600: "шестисот",
        700: "семисот", 800: "восьмисот", 900: "девятисот"
    ]
    private static let stressed: Set<Int> = [2, 6, 7, 8, 40]
    private static let pattern = try! NSRegularExpression(
        pattern: "(?<![0-9.,])([0-9]{1,4})-(" + endings.map(\.0).joined(separator: "|") + ")(?![А-Яа-яЁё0-9])")

    public static func expandOrdinals(_ text: String) -> String {
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let numberRange = Range(match.range(at: 1), in: result),
                  let endingRange = Range(match.range(at: 2), in: result), let number = Int(result[numberRange]),
                  let form = endings.first(where: { $0.0 == result[endingRange] })?.1, let words = ordinal(number, form) else { continue }
            result.replaceSubrange(whole, with: words)
        }
        return result
    }

    private static func ordinal(_ number: Int, _ form: Form) -> String? {
        guard number > 0, number < 10_000 else { return nil }
        let thousands = number / 1000 * 1000, hundreds = number % 1000 / 100 * 100, rest = number % 100
        var prefix: [Int] = [], last: Int
        if rest == 0 {
            guard hundreds > 0 else { return nil } // "2000-й" needs compound stems; leave it for the voice.
            last = hundreds
        } else if rest < 20 || rest % 10 == 0 {
            if hundreds > 0 { prefix.append(hundreds) }
            last = rest
        } else {
            if hundreds > 0 { prefix.append(hundreds) }
            prefix.append(rest / 10 * 10); last = rest % 10
        }
        guard let stem = stems[last] else { return nil }
        let cardinals = (thousands > 0 ? [cardinal(thousands)] : []) + prefix.map(cardinal)
        guard !cardinals.contains(nil) else { return nil }
        return (cardinals.compactMap { $0 } + [stem + ending(form, soft: last == 3, stressed: stressed.contains(last))]).joined(separator: " ")
    }

    private static func cardinal(_ value: Int) -> String? {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "ru"); formatter.numberStyle = .spellOut
        guard var words = formatter.string(from: NSNumber(value: value)) else { return nil }
        if words.hasPrefix("одна тысяча") { words = String(words.dropFirst(5)) }
        return words.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) ? nil : words
    }

    private static func ending(_ form: Form, soft: Bool, stressed: Bool) -> String {
        if soft {
            switch form {
            case .masculine: return "ий"
            case .genitive: return "ьего"
            case .dative: return "ьему"
            case .prepositional: return "ьем"
            case .instrumental: return "ьим"
            case .neuter: return "ье"
            case .feminine: return "ья"
            case .feminineAccusative: return "ью"
            case .pluralGenitive: return "ьих"
            case .pluralInstrumental: return "ьими"
            }
        }
        switch form {
        case .masculine: return stressed ? "ой" : "ый"
        case .genitive: return "ого"
        case .dative: return "ому"
        case .prepositional: return "ом"
        case .instrumental: return "ым"
        case .neuter: return "ое"
        case .feminine: return "ая"
        case .feminineAccusative: return "ую"
        case .pluralGenitive: return "ых"
        case .pluralInstrumental: return "ыми"
        }
    }
}
