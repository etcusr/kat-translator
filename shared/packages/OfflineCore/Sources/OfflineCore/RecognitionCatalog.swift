import Foundation

public enum RecognitionCatalog {
    public static let ultraID = "asr-parakeet-ultra"
    // Exact upstream Ultra language set; no inferred dialect/script aliases.
    public static let ultraLanguages: Set<String> = ["en", "de", "fr", "es", "it", "pt", "ru", "uk", "hr", "sl", "lv", "lt", "et", "fi", "sv", "da", "nl", "pl", "cs", "sk", "hu", "ro", "bg", "el", "mt"]
    // Ultra can infer the source from its multilingual output when no language is forced.
    public static func prefersUltra(_ language: SpeechLanguage?) -> Bool {
        language.map { ultraLanguages.contains($0.rawValue) } ?? true
    }

    // Exact language/script matches from Meta's language list; no inferred dialect fallbacks.
    public static let omnilingualCodes: [String: String] = [
        "anp": "anp_Deva",
        "apc": "apc_Arab",
        "ars": "ars_Arab",
        "ary": "ary_Arab",
        "arz": "arz_Arab",
        "ast": "ast_Latn",
        "ban": "ban_Latn",
        "bew": "bew_Latn",
        "ceb": "ceb_Latn",
        "ckb": "ckb_Arab",
        "cnh": "cnh_Latn",
        "cv": "chv_Cyrl",
        "dv": "div_Thaa",
        "eo": "epo_Latn",
        "fy": "fry_Latn",
        "ga": "gle_Latn",
        "hif": "hif_Latn",
        "hil": "hil_Latn",
        "hsb": "hsb_Latn",
        "hyw": "hyw_Armn",
        "ig": "ibo_Latn",
        "ku": "kmr_Latn",
        "ky": "kir_Cyrl",
        "lus": "lus_Latn",
        "nap": "nap_Latn",
        "ny": "nya_Latn",
        "or": "ory_Orya",
        "os": "oss_Cyrl",
        "pap": "pap_Latn",
        "rn": "run_Latn",
        "rw": "kin_Latn",
        "sah": "sah_Cyrl",
        "sm": "smo_Latn",
        "ti": "tir_Ethi",
        "ug": "uig_Arab",
        "ur-Latn": "urd_Latn",
        "xh": "xho_Latn",
        "zh-Hant": "cmn_Hant",
        "zu": "zul_Latn",
    ]
}
extension SpeechLanguage {
    public var supportsRecognition: Bool { whisperCode != nil || RecognitionCatalog.omnilingualCodes[rawValue] != nil }
}
public enum RecognitionPreference: String, CaseIterable, Sendable {
    case automatic, ultra, whisper

    public static func restoredSelection(_ value: String?) -> Self {
        // Preserve explicit Whisper selection when migrating away from retired experimental engines.
        if value == "whisperKit" || value == "apple" { return .whisper }
        return value.flatMap(Self.init(rawValue:)) ?? .automatic
    }
}

public enum RecognitionError: LocalizedError {
    case downloadRequired
    public var errorDescription: String? { L10n.text("Скачайте распознавание для выбранного языка в разделе «Модели».") }
}
