import Foundation

public enum TranslationInput: String, Sendable { case voice, text, camera }

/// Language identities are independent of model, ASR, voice and OCR capabilities.
public struct TranslationLanguage: Identifiable, Sendable {
    public let id: String
    public let name: String
    public var displayName: String {
        if L10n.language == "ru" { return name }
        if L10n.language == "en" { return englishName }
        return L10n.locale.localizedString(forLanguageCode: id) ?? englishName
    }
    public let englishName: String
    public let indexName: String?
    public let whisperCode: String?
    public let hasVoice: Bool
    public let mil: Bool
    public var available: Bool { id != "zh-Hant" }
    public var nativeName: String { Locale(identifier: id).localizedString(forLanguageCode: id) ?? englishName }
    public func connected(to model: TranslationModel) -> Bool {
        guard available else { return false }
        switch model {
        case .opusBig: return ["en", "ru", "uk", "be"].contains(id)
        case .index9B, .index2B: return indexName != nil
        case .opusDirections: return OpusDirectionRoutes.languages.contains(id)
        case .qwen9B: return true // Expanded manual trials; not a claim of verified translation quality.
        case .mil4B, .mil12B: return mil
        case .gemma4B: return Set(["ru", "en", "zh", "de", "fr", "es", "ja", "ko", "pt", "ar", "it", "tr", "hi", "th"]).contains(id)
        }
    }
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || [displayName, name, englishName, nativeName, id].contains {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: L10n.locale) != nil
        }
    }
    /// Auto must not inherit the language restrictions of the currently loaded engine.
    public static func selectable(for model: TranslationModel, automatic: Bool) -> [TranslationLanguage] {
        automatic ? catalog.filter { item in item.available && TranslationModel.selectable.contains { item.connected(to: $0) } } : supported(by: model)
    }
    public static func supported(by model: TranslationModel) -> [TranslationLanguage] {
        catalog.filter { $0.connected(to: model) }
    }
    public static func name(_ id: String) -> String { byID[id]?.displayName ?? id }
    /// Compact card label; script variants remain distinguishable from the base language.
    public static func shortCode(_ id: String) -> String {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        let base = parts.first ?? id
        let code = Locale.LanguageCode(base).identifier(.alpha3) ?? base
        return parts.count == 2 ? code + "-" + parts[1].lowercased() : code
    }
    public static func details(_ language: SpeechLanguage) -> TranslationLanguage { byID[language.rawValue]! }
    private static let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    // Source: official Index demo language table; aliases merged. See docs/benchmarks/language-catalog.
    public static let catalog: [TranslationLanguage] = [
        .init(id: "en", name: "Английский", englishName: "English", indexName: "英语", whisperCode: "en", hasVoice: true, mil: true),
        .init(id: "zh", name: "Китайский", englishName: "Chinese", indexName: "中文", whisperCode: "zh", hasVoice: true, mil: true),
        .init(id: "de", name: "Немецкий", englishName: "German", indexName: "德语", whisperCode: "de", hasVoice: true, mil: true),
        .init(id: "fr", name: "Французский", englishName: "French", indexName: "法语", whisperCode: "fr", hasVoice: true, mil: true),
        .init(id: "es", name: "Испанский", englishName: "Spanish", indexName: "西班牙语", whisperCode: "es", hasVoice: true, mil: true),
        .init(id: "ja", name: "Японский", englishName: "Japanese", indexName: "日语", whisperCode: "ja", hasVoice: true, mil: true),
        .init(id: "ko", name: "Корейский", englishName: "Korean", indexName: "韩语", whisperCode: "ko", hasVoice: true, mil: true),
        .init(id: "pt", name: "Португальский", englishName: "Portuguese", indexName: "葡萄牙语", whisperCode: "pt", hasVoice: true, mil: true),
        .init(id: "ru", name: "Русский", englishName: "Russian", indexName: "俄语", whisperCode: "ru", hasVoice: true, mil: true),
        .init(id: "ar", name: "Арабский", englishName: "Arabic", indexName: "阿拉伯语", whisperCode: "ar", hasVoice: true, mil: true),
        .init(id: "it", name: "Итальянский", englishName: "Italian", indexName: "意大利语", whisperCode: "it", hasVoice: true, mil: true),
        .init(id: "nl", name: "Нидерландский", englishName: "Dutch", indexName: "荷兰语", whisperCode: "nl", hasVoice: true, mil: true),
        .init(id: "pl", name: "Польский", englishName: "Polish", indexName: "波兰语", whisperCode: "pl", hasVoice: true, mil: true),
        .init(id: "ro", name: "Румынский", englishName: "Romanian", indexName: "罗马尼亚语", whisperCode: "ro", hasVoice: true, mil: true),
        .init(id: "sv", name: "Шведский", englishName: "Swedish", indexName: "瑞典语", whisperCode: "sv", hasVoice: true, mil: true),
        .init(id: "tr", name: "Турецкий", englishName: "Turkish", indexName: "土耳其语", whisperCode: "tr", hasVoice: true, mil: true),
        .init(id: "hi", name: "Хинди", englishName: "Hindi", indexName: "印地语", whisperCode: "hi", hasVoice: true, mil: true),
        .init(id: "vi", name: "Вьетнамский", englishName: "Vietnamese", indexName: "越南语", whisperCode: "vi", hasVoice: true, mil: true),
        .init(id: "th", name: "Тайский", englishName: "Thai", indexName: "泰语", whisperCode: "th", hasVoice: true, mil: true),
        .init(id: "id", name: "Индонезийский", englishName: "Indonesian", indexName: "印尼语", whisperCode: "id", hasVoice: true, mil: true),
        .init(id: "ms", name: "Малайский", englishName: "Malay", indexName: "马来语", whisperCode: "ms", hasVoice: true, mil: true),
        .init(id: "tl", name: "Тагальский", englishName: "Filipino", indexName: "菲律宾语", whisperCode: "tl", hasVoice: true, mil: true),
        .init(id: "uk", name: "Украинский", englishName: "Ukrainian", indexName: "乌克兰语", whisperCode: "uk", hasVoice: true, mil: false),
        .init(id: "fa", name: "Персидский", englishName: "Persian", indexName: "波斯语", whisperCode: "fa", hasVoice: true, mil: true),
        .init(id: "cs", name: "Чешский", englishName: "Czech", indexName: "捷克语", whisperCode: "cs", hasVoice: true, mil: true),
        .init(id: "el", name: "Греческий", englishName: "Greek", indexName: "希腊语", whisperCode: "el", hasVoice: true, mil: true),
        .init(id: "da", name: "Датский", englishName: "Danish", indexName: "丹麦语", whisperCode: "da", hasVoice: true, mil: true),
        .init(id: "hu", name: "Венгерский", englishName: "Hungarian", indexName: "匈牙利语", whisperCode: "hu", hasVoice: true, mil: true),
        .init(id: "fi", name: "Финский", englishName: "Finnish", indexName: "芬兰语", whisperCode: "fi", hasVoice: true, mil: true),
        .init(id: "no", name: "Норвежский (букмол)", englishName: "Norwegian Bokmål", indexName: "书面挪威语", whisperCode: "no", hasVoice: true, mil: true),
        .init(id: "sk", name: "Словацкий", englishName: "Slovak", indexName: "斯洛伐克语", whisperCode: "sk", hasVoice: true, mil: true),
        .init(id: "bg", name: "Болгарский", englishName: "Bulgarian", indexName: "保加利亚语", whisperCode: "bg", hasVoice: true, mil: true),
        .init(id: "bs", name: "Боснийский", englishName: "Bosnian", indexName: "波斯尼亚语", whisperCode: "bs", hasVoice: false, mil: false),
        .init(id: "ca", name: "Каталанский", englishName: "Catalan", indexName: "加泰罗尼亚语", whisperCode: "ca", hasVoice: true, mil: true),
        .init(id: "bn", name: "Бенгальский", englishName: "Bengali", indexName: "孟加拉语", whisperCode: "bn", hasVoice: true, mil: true),
        .init(id: "he", name: "Иврит", englishName: "Hebrew", indexName: "希伯来语", whisperCode: "he", hasVoice: true, mil: true),
        .init(id: "lt", name: "Литовский", englishName: "Lithuanian", indexName: "立陶宛语", whisperCode: "lt", hasVoice: true, mil: false),
        .init(id: "sl", name: "Словенский", englishName: "Slovenian", indexName: "斯洛文尼亚语", whisperCode: "sl", hasVoice: true, mil: true),
        .init(id: "et", name: "Эстонский", englishName: "Estonian", indexName: "爱沙尼亚语", whisperCode: "et", hasVoice: true, mil: false),
        .init(id: "sq", name: "Албанский", englishName: "Albanian", indexName: "阿尔巴尼亚语", whisperCode: "sq", hasVoice: true, mil: false),
        .init(id: "lv", name: "Латышский", englishName: "Latvian", indexName: "拉脱维亚语", whisperCode: "lv", hasVoice: true, mil: false),
        .init(id: "az", name: "Азербайджанский", englishName: "Azerbaijani", indexName: "阿塞拜疆语", whisperCode: "az", hasVoice: false, mil: true),
        .init(id: "hr", name: "Хорватский", englishName: "Croatian", indexName: "克罗地亚语", whisperCode: "hr", hasVoice: true, mil: true),
        .init(id: "ta", name: "Тамильский", englishName: "Tamil", indexName: "泰米尔语", whisperCode: "ta", hasVoice: true, mil: true),
        .init(id: "ne", name: "Непальский", englishName: "Nepali", indexName: "尼泊尔语", whisperCode: "ne", hasVoice: true, mil: false),
        .init(id: "ur", name: "Урду", englishName: "Urdu", indexName: "乌尔都语", whisperCode: "ur", hasVoice: true, mil: true),
        .init(id: "mk", name: "Македонский", englishName: "Macedonian", indexName: "马其顿语", whisperCode: "mk", hasVoice: true, mil: false),
        .init(id: "sr", name: "Сербский (кириллица)", englishName: "Serbian (Cyrillic)", indexName: "塞尔维亚语（西里尔）", whisperCode: "sr", hasVoice: true, mil: false),
        .init(id: "mr", name: "Маратхи", englishName: "Marathi", indexName: "马拉地语", whisperCode: "mr", hasVoice: true, mil: false),
        .init(id: "ka", name: "Грузинский", englishName: "Georgian", indexName: "格鲁吉亚语", whisperCode: "ka", hasVoice: true, mil: false),
        .init(id: "ml", name: "Малаялам", englishName: "Malayalam", indexName: "马拉雅拉姆语", whisperCode: "ml", hasVoice: true, mil: false),
        .init(id: "kk", name: "Казахский", englishName: "Kazakh", indexName: "哈萨克语", whisperCode: "kk", hasVoice: true, mil: true),
        .init(id: "is", name: "Исландский", englishName: "Icelandic", indexName: "冰岛语", whisperCode: "is", hasVoice: true, mil: false),
        .init(id: "gl", name: "Галисийский", englishName: "Galician", indexName: "加利西亚语", whisperCode: "gl", hasVoice: true, mil: false),
        .init(id: "kn", name: "Каннада", englishName: "Kannada", indexName: "卡纳达语", whisperCode: "kn", hasVoice: true, mil: false),
        .init(id: "ary", name: "Арабский (марокканский)", englishName: "Moroccan Arabic", indexName: "摩洛哥阿拉伯语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "gu", name: "Гуджарати", englishName: "Gujarati", indexName: "古吉拉特语", whisperCode: "gu", hasVoice: true, mil: false),
        .init(id: "be", name: "Белорусский", englishName: "Belarusian", indexName: "白俄罗斯语", whisperCode: "be", hasVoice: false, mil: false),
        .init(id: "af", name: "Африкаанс", englishName: "Afrikaans", indexName: "南非荷兰语", whisperCode: "af", hasVoice: false, mil: false),
        .init(id: "hy", name: "Армянский", englishName: "Armenian", indexName: "亚美尼亚语", whisperCode: "hy", hasVoice: true, mil: false),
        .init(id: "mn", name: "Монгольский", englishName: "Mongolian", indexName: "蒙古语", whisperCode: "mn", hasVoice: true, mil: false),
        .init(id: "km", name: "Кхмерский", englishName: "Khmer", indexName: "高棉语", whisperCode: "km", hasVoice: true, mil: true),
        .init(id: "eu", name: "Баскский", englishName: "Basque", indexName: "巴斯克语", whisperCode: "eu", hasVoice: true, mil: false),
        .init(id: "my", name: "Бирманский", englishName: "Burmese", indexName: "缅甸语", whisperCode: "my", hasVoice: true, mil: true),
        .init(id: "la", name: "Латинский", englishName: "Latin", indexName: "拉丁语", whisperCode: "la", hasVoice: true, mil: false),
        .init(id: "uz-Cyrl", name: "Узбекский (кириллица)", englishName: "Uzbek (Cyrillic)", indexName: "乌兹别克语（西里尔）", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "te", name: "Телугу", englishName: "Telugu", indexName: "泰卢固语", whisperCode: "te", hasVoice: true, mil: false),
        .init(id: "or", name: "Ория", englishName: "Odia", indexName: "奥里亚语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "nn", name: "Норвежский (нюнорск)", englishName: "Norwegian Nynorsk", indexName: "新挪威语", whisperCode: "nn", hasVoice: false, mil: false),
        .init(id: "uz", name: "Узбекский", englishName: "Uzbek", indexName: "乌兹别克语", whisperCode: "uz", hasVoice: false, mil: true),
        .init(id: "sw", name: "Суахили", englishName: "Swahili", indexName: "斯瓦希里语", whisperCode: "sw", hasVoice: true, mil: false),
        .init(id: "si", name: "Сингальский", englishName: "Sinhala", indexName: "僧伽罗语", whisperCode: "si", hasVoice: false, mil: false),
        .init(id: "ky", name: "Киргизский", englishName: "Kyrgyz", indexName: "吉尔吉斯语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "so", name: "Сомалийский", englishName: "Somali", indexName: "索马里语", whisperCode: "so", hasVoice: true, mil: false),
        .init(id: "pa", name: "Панджаби", englishName: "Punjabi", indexName: "旁遮普语", whisperCode: "pa", hasVoice: true, mil: false),
        .init(id: "arz", name: "Арабский (египетский)", englishName: "Egyptian Arabic", indexName: "埃及阿拉伯语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "cy", name: "Валлийский", englishName: "Welsh", indexName: "威尔士语", whisperCode: "cy", hasVoice: true, mil: false),
        .init(id: "nrm", name: "Нормандский", englishName: "Norman", indexName: "诺曼语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "ps", name: "Пушту", englishName: "Pashto", indexName: "普什图语", whisperCode: "ps", hasVoice: true, mil: false),
        .init(id: "ga", name: "Ирландский", englishName: "Irish", indexName: "爱尔兰语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "sr-Latn", name: "Сербский (латиница)", englishName: "Serbian (Latin)", indexName: "塞尔维亚语（拉丁）", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "ha", name: "Хауса", englishName: "Hausa", indexName: "豪萨语", whisperCode: "ha", hasVoice: true, mil: false),
        .init(id: "ckb", name: "Курдский (сорани)", englishName: "Central Kurdish", indexName: "中库尔德语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "mt", name: "Мальтийский", englishName: "Maltese", indexName: "马耳他语", whisperCode: "mt", hasVoice: true, mil: false),
        .init(id: "yue", name: "Кантонский", englishName: "Cantonese", indexName: "粤语", whisperCode: "yue", hasVoice: false, mil: true),
        .init(id: "tg", name: "Таджикский", englishName: "Tajik", indexName: "塔吉克语", whisperCode: "tg", hasVoice: true, mil: false),
        .init(id: "ku", name: "Курдский (курманджи)", englishName: "Northern Kurdish", indexName: "北库尔德语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "bew", name: "Бетави", englishName: "Betawi", indexName: "贝塔维语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "am", name: "Амхарский", englishName: "Amharic", indexName: "阿姆哈拉语", whisperCode: "am", hasVoice: true, mil: false),
        .init(id: "lo", name: "Лаосский", englishName: "Lao", indexName: "老挝语", whisperCode: "lo", hasVoice: true, mil: true),
        .init(id: "lb", name: "Люксембургский", englishName: "Luxembourgish", indexName: "卢森堡语", whisperCode: "lb", hasVoice: true, mil: false),
        .init(id: "fy", name: "Фризский", englishName: "Frisian", indexName: "弗里西语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "dv", name: "Дивехи", englishName: "Dhivehi", indexName: "迪维希语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "eo", name: "Эсперанто", englishName: "Esperanto", indexName: "世界语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "rw", name: "Киньяруанда", englishName: "Kinyarwanda", indexName: "卢旺达语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "ars", name: "Арабский (недждийский)", englishName: "Najdi Arabic", indexName: "内志阿拉伯语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "fo", name: "Фарерский", englishName: "Faroese", indexName: "法罗语", whisperCode: "fo", hasVoice: true, mil: false),
        .init(id: "mg", name: "Малагасийский", englishName: "Malagasy", indexName: "马达加斯加语", whisperCode: "mg", hasVoice: true, mil: false),
        .init(id: "as", name: "Ассамский", englishName: "Assamese", indexName: "阿萨姆语", whisperCode: "as", hasVoice: true, mil: false),
        .init(id: "sd", name: "Синдхи", englishName: "Sindhi", indexName: "信德语", whisperCode: "sd", hasVoice: false, mil: false),
        .init(id: "xh", name: "Коса", englishName: "Xhosa", indexName: "科萨语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "tk", name: "Туркменский", englishName: "Turkmen", indexName: "土库曼语", whisperCode: "tk", hasVoice: false, mil: false),
        .init(id: "ht", name: "Гаитянский креольский", englishName: "Haitian Creole", indexName: "海地克里奥尔语", whisperCode: "ht", hasVoice: true, mil: false),
        .init(id: "gd", name: "Шотландский гэльский", englishName: "Scottish Gaelic", indexName: "苏格兰盖尔语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "ceb", name: "Себуанский", englishName: "Cebuano", indexName: "宿务语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "yi", name: "Идиш", englishName: "Yiddish", indexName: "意第绪语", whisperCode: "yi", hasVoice: false, mil: false),
        .init(id: "jv", name: "Яванский", englishName: "Javanese", indexName: "爪哇语", whisperCode: "jw", hasVoice: true, mil: false),
        .init(id: "ba", name: "Башкирский", englishName: "Bashkir", indexName: "巴什基尔语", whisperCode: "ba", hasVoice: true, mil: false),
        .init(id: "pap", name: "Папьяменто", englishName: "Papiamento", indexName: "帕皮阿门托语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "mi", name: "Маори", englishName: "Māori", indexName: "毛利语", whisperCode: "mi", hasVoice: false, mil: false),
        .init(id: "ug", name: "Уйгурский", englishName: "Uyghur", indexName: "维吾尔语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "tt", name: "Татарский", englishName: "Tatar", indexName: "鞑靼语", whisperCode: "tt", hasVoice: true, mil: false),
        .init(id: "bo", name: "Тибетский", englishName: "Tibetan", indexName: "藏语", whisperCode: "bo", hasVoice: true, mil: false),
        .init(id: "mww", name: "Хмонг-дау", englishName: "Hmong Daw", indexName: "白苗语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "hyw", name: "Западноармянский", englishName: "Western Armenian", indexName: "西亚美尼亚语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "yo", name: "Йоруба", englishName: "Yoruba", indexName: "约鲁巴语", whisperCode: "yo", hasVoice: true, mil: false),
        .init(id: "zu", name: "Зулу", englishName: "Zulu", indexName: "祖鲁语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "sdh", name: "Курдский (южный)", englishName: "Southern Kurdish", indexName: "南库尔德语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "sm", name: "Самоанский", englishName: "Samoan", indexName: "萨摩亚语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "co", name: "Корсиканский", englishName: "Corsican", indexName: "科西嘉语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "hif", name: "Фиджийский хинди", englishName: "Fiji Hindi", indexName: "斐济印地语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "su", name: "Сунданский", englishName: "Sundanese", indexName: "巽他语", whisperCode: "su", hasVoice: true, mil: false),
        .init(id: "ny", name: "Ньянджа", englishName: "Chichewa", indexName: "齐切瓦语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "ig", name: "Игбо", englishName: "Igbo", indexName: "伊博语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "haw", name: "Гавайский", englishName: "Hawaiian", indexName: "夏威夷语", whisperCode: "haw", hasVoice: true, mil: false),
        .init(id: "st", name: "Сесото", englishName: "Sesotho", indexName: "塞索托语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "lus", name: "Мизо", englishName: "Mizo", indexName: "米佐语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "sn", name: "Шона", englishName: "Shona", indexName: "绍纳语", whisperCode: "sn", hasVoice: true, mil: false),
        .init(id: "cv", name: "Чувашский", englishName: "Chuvash", indexName: "楚瓦什语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "azb", name: "Азербайджанский (южный)", englishName: "South Azerbaijani", indexName: "南阿塞拜疆语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "rm", name: "Романшский", englishName: "Romansh", indexName: "罗曼什语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "rn", name: "Кирунди", englishName: "Rundi", indexName: "基隆迪语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "hi-Latn", name: "Хинди (латиница)", englishName: "Hindi (Latin)", indexName: "印地语（拉丁）", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "sah", name: "Якутский", englishName: "Yakut", indexName: "雅库特语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "ti", name: "Тигринья", englishName: "Tigrinya", indexName: "提格利尼亚语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "ast", name: "Астурийский", englishName: "Asturian", indexName: "阿斯图里亚斯语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "oc", name: "Окситанский", englishName: "Occitan", indexName: "奥克语", whisperCode: "oc", hasVoice: false, mil: false),
        .init(id: "cnh", name: "Чинский (хака)", englishName: "Hakha Chin", indexName: "钦语（哈卡）", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "se", name: "Северносаамский", englishName: "Northern Sami", indexName: "北萨米语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "nds", name: "Нижненемецкий", englishName: "Low German", indexName: "低地德语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "os", name: "Осетинский", englishName: "Ossetian", indexName: "奥塞梯语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "ur-Latn", name: "Урду (латиница)", englishName: "Urdu (Latin)", indexName: "乌尔都语（拉丁）", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "gsw", name: "Швейцарский немецкий", englishName: "Swiss German", indexName: "瑞士德语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "anp", name: "Анги́ка", englishName: "Angika", indexName: "昂加语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "apc", name: "Арабский (левантийский)", englishName: "Levantine Arabic", indexName: "黎凡特阿拉伯语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "om", name: "Оромо", englishName: "Oromo", indexName: "奥罗莫语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "nap", name: "Неаполитанский", englishName: "Neapolitan", indexName: "那不勒斯语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "hsb", name: "Верхнелужицкий", englishName: "Upper Sorbian", indexName: "上索布语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "hil", name: "Хилигайнон", englishName: "Hiligaynon", indexName: "希利盖农语", whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "kl", name: "Гренландский", englishName: "Greenlandic", indexName: "格陵兰语", whisperCode: nil, hasVoice: false, mil: false),
        .init(id: "ban", name: "Балийский", englishName: "Balinese", indexName: nil, whisperCode: nil, hasVoice: true, mil: false),
        .init(id: "zh-Hant", name: "Китайский (традиционный)", englishName: "Chinese (Traditional)", indexName: nil, whisperCode: nil, hasVoice: false, mil: true),
    ]
}

public struct LanguageSelection: Equatable, Sendable {
    public private(set) var sourceID: String
    public private(set) var targetID: String
    public var automaticRequested: Bool
    public init(sourceID: String = "ru", targetID: String = "en", automaticRequested: Bool = false) {
        self.sourceID = sourceID == "zh-Hant" ? "zh" : sourceID; self.targetID = targetID == "zh-Hant" ? "zh" : targetID; self.automaticRequested = automaticRequested
    }
    // Explicit source and target are passed through every backend and archive entry.
    public var isAvailable: Bool { SpeechLanguage(rawValue: sourceID) != nil && SpeechLanguage(rawValue: targetID) != nil }
    public func connected(to model: TranslationModel) -> Bool {
        guard let source = runtimeSource, let target = runtimeTarget else { return false }
        return model.supports(source: source, target: target)
    }
    public var supportsAutomatic: Bool { isAvailable }
    public func automaticActive(in mode: TranslationInput) -> Bool { supportsAutomatic && automaticRequested }
    public var runtimeSource: SpeechLanguage? { isAvailable ? SpeechLanguage(rawValue: sourceID) : nil }
    public var runtimeTarget: SpeechLanguage? { isAvailable ? SpeechLanguage(rawValue: targetID) : nil }
    public mutating func reverse() { (sourceID, targetID) = (targetID, sourceID) }
    public mutating func selectSource(_ id: String) {
        automaticRequested = false
        if id == targetID { reverse() } else { sourceID = id }
    }
    public mutating func selectTarget(_ id: String) {
        if id == sourceID { reverse() } else { targetID = id }
    }
}
