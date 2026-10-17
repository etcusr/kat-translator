import Foundation

/// Russian speech text: ordinals written with a hyphenated ending ("16-е", "15-го", "2026-м")
/// are spelled out before synthesis when their grammatical form is known.
/// Ambiguous abbreviations are preserved unless adjacent words resolve them.
public enum RussianSpeechText {
    private enum Form {
        case masculine, genitive, dative, prepositional, instrumental, neuter
        case feminine, feminineAccusative, feminineOblique, plural, pluralGenitive, pluralInstrumental
        case ambiguousY, ambiguousM, ambiguousE
    }
    private static let endings: [(String, Form)] = [
        ("ыми", .pluralInstrumental), ("ими", .pluralInstrumental), ("ми", .pluralInstrumental),
        ("ого", .genitive), ("его", .genitive), ("го", .genitive),
        ("ому", .dative), ("ему", .dative), ("му", .dative),
        ("ый", .masculine), ("ий", .masculine), ("ой", .ambiguousY), ("й", .ambiguousY),
        ("ым", .instrumental), ("им", .instrumental), ("ом", .prepositional), ("ем", .prepositional), ("м", .ambiguousM),
        ("ое", .neuter), ("ее", .neuter), ("е", .ambiguousE),
        ("ые", .plural), ("ие", .plural), ("и", .plural),
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

    // A deliberately bounded vocabulary: suffix-only guesses misclassify words such as
    // "линии" (feminine oblique or plural) and indeclinable street names such as "авеню".
    private static let masculineNouns: Set<String> = [
        "этаж", "раз", "рейс", "класс", "день", "год", "номер", "пункт", "дом", "час",
        "поезд", "вагон", "путь", "вариант", "том", "вопрос", "приз", "квартал", "месяц"
    ]
    private static let feminineObliqueNouns: Set<String> = [
        "улицы", "улице", "улицей", "остановки", "остановке", "остановкой",
        "станции", "станцией", "линии", "линией", "школы", "школе", "школой",
        "страницы", "странице", "страницей", "попытки", "попытке", "попыткой",
        "недели", "неделе", "неделей", "главы", "главе", "главой"
    ]
    private static let neuterNouns: Set<String> = ["число", "место", "окно", "здание", "задание", "упражнение"]
    private static let pluralNouns: Set<String> = [
        "годы", "дни", "места", "числа", "этажи", "рейсы", "классы", "номера", "дома",
        "страницы", "улицы", "школы", "станции", "линии", "недели", "окна", "здания", "задания", "упражнения"
    ]
    private static let months: Set<String> = [
        "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
        "сентября", "октября", "ноября", "декабря"
    ]

    public static func expandOrdinals(_ text: String) -> String {
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let originalRange = Range(match.range, in: text), let whole = Range(match.range, in: result),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let endingRange = Range(match.range(at: 2), in: text), let number = Int(text[numberRange]),
                  let candidate = endings.first(where: { $0.0 == text[endingRange] })?.1,
                  let form = resolve(candidate, number: number, before: text[..<originalRange.lowerBound],
                                     after: text[originalRange.upperBound...]),
                  let words = ordinal(number, form) else { continue }
            result.replaceSubrange(whole, with: words)
        }
        return result
    }

    private static func resolve(_ form: Form, number: Int, before: Substring, after: Substring) -> Form? {
        // Do not infer agreement across punctuation, intervening adjectives, or a newline.
        let following = after.drop(while: { $0 == " " || $0 == "\t" })
        let nextWord = String(following.prefix(while: \.isLetter)).lowercased()
        switch form {
        case .ambiguousY:
            if feminineObliqueNouns.contains(nextWord) { return .feminineOblique }
            if masculineNouns.contains(nextWord) { return .masculine }
            return nil
        case .ambiguousM:
            guard !nextWord.isEmpty, !["и", "или", "а", "но"].contains(nextWord) else { return nil }
            let previous = before.reversed().drop(while: { $0 == " " || $0 == "\t" })
            let preposition = String(previous.prefix(while: \.isLetter).reversed()).lowercased()
            if ["в", "во", "на", "о", "об", "обо", "при"].contains(preposition) { return .prepositional }
            if ["перед", "пред", "над", "под", "за", "с", "со", "между"].contains(preposition) { return .instrumental }
            return nil
        case .ambiguousE:
            if pluralNouns.contains(nextWord) { return .plural }
            if neuterNouns.contains(nextWord) { return .neuter }
            guard (1...31).contains(number) else { return nil }
            if months.contains(nextWord) { return .neuter }
            // Retain the conventional day-of-month reading of bare "16-е", including
            // date corrections such as "17-е, а не 16-е". Other noun contexts stay intact.
            if following.isEmpty || following.first.map({ ".,;:!?".contains($0) }) == true { return .neuter }
            return nil
        default:
            return form
        }
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
            case .feminineOblique: return "ьей"
            case .plural: return "ьи"
            case .pluralGenitive: return "ьих"
            case .pluralInstrumental: return "ьими"
            case .ambiguousY, .ambiguousM, .ambiguousE: preconditionFailure("Unresolved ordinal form")
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
        case .feminineOblique: return "ой"
        case .plural: return "ые"
        case .pluralGenitive: return "ых"
        case .pluralInstrumental: return "ыми"
        case .ambiguousY, .ambiguousM, .ambiguousE: preconditionFailure("Unresolved ordinal form")
        }
    }
}
