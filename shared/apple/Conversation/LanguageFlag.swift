import SwiftUI

/// Decorative geographic cues, never locale/dialect selection or model capabilities.
/// Script variants are explicit: a script alone must not imply a different country.
enum LanguageFlag {
    static func symbol(for languageID: String) -> String {
        guard let region = regions[languageID] else { return "🌐" }
        return String(String.UnicodeScalarView(region.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }))
    }

    private static let regions: [String: String] = {
        let groups: [String: [String]] = [
            "GB": ["en", "cy", "gd"], "CN": ["zh"], "DE": ["de", "nds", "hsb"],
            "FR": ["fr", "co", "oc"], "ES": ["es", "ca", "gl", "ast"],
            "JP": ["ja"], "KR": ["ko"], "PT": ["pt"],
            "RU": ["ru", "ba", "tt", "cv", "sah"], "IT": ["it", "nap"],
            "NL": ["nl", "fy"], "PL": ["pl"], "RO": ["ro"], "SE": ["sv"],
            "TR": ["tr"], "IN": ["hi", "hi-Latn", "ta", "mr", "ml", "kn", "gu", "te", "or", "as", "lus", "anp"],
            "VN": ["vi"], "TH": ["th"], "ID": ["id", "bew", "jv", "su", "ban"],
            "MY": ["ms"], "PH": ["tl", "ceb", "hil"], "UA": ["uk"], "IR": ["fa", "azb"],
            "CZ": ["cs"], "GR": ["el"], "DK": ["da"], "HU": ["hu"], "FI": ["fi"],
            "NO": ["no", "nn"], "SK": ["sk"], "BG": ["bg"], "BA": ["bs"],
            "BD": ["bn"], "IL": ["he"], "LT": ["lt"], "SI": ["sl"], "EE": ["et"],
            "AL": ["sq"], "LV": ["lv"], "AZ": ["az"], "HR": ["hr"], "NP": ["ne"],
            "PK": ["ur", "ur-Latn", "sd"], "MK": ["mk"], "RS": ["sr", "sr-Latn"],
            "GE": ["ka"], "KZ": ["kk"], "IS": ["is"], "MA": ["ary"], "BY": ["be"],
            "ZA": ["af", "xh", "zu"], "AM": ["hy"], "MN": ["mn"], "KH": ["km"],
            "MM": ["my", "cnh"], "UZ": ["uz", "uz-Cyrl"], "LK": ["si"], "KG": ["ky"],
            "SO": ["so"], "EG": ["arz"], "AF": ["ps"], "IE": ["ga"], "NG": ["ha", "yo", "ig"],
            "MT": ["mt"], "HK": ["yue"], "TJ": ["tg"], "ET": ["am", "om"], "LA": ["lo"],
            "LU": ["lb"], "MV": ["dv"], "RW": ["rw"], "SA": ["ars"], "FO": ["fo"],
            "MG": ["mg"], "TM": ["tk"], "HT": ["ht"], "NZ": ["mi"], "WS": ["sm"],
            "FJ": ["hif"], "MW": ["ny"], "US": ["haw"], "LS": ["st"], "ZW": ["sn"],
            "CH": ["rm", "gsw"], "BI": ["rn"], "GL": ["kl"]
        ]
        // Arabic, Kurdish, Esperanto, Latin and other transnational/ambiguous
        // associations intentionally fall back to a globe, including unknown IDs.
        return Dictionary(uniqueKeysWithValues: groups.flatMap { region, languages in
            languages.map { ($0, region) }
        })
    }()
}

struct LanguageFlagBadge: View {
    let languageID: String
    var compact = false

    var body: some View {
        Text(LanguageFlag.symbol(for: languageID))
            .font(.system(size: compact ? 18 : 22))
            .lineLimit(1).fixedSize()
            .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
            .accessibilityHidden(true)
    }
}
