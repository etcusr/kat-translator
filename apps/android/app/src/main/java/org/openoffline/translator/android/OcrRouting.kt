package org.openoffline.translator.android

object OcrRouting {
    enum class Script { LATIN, CHINESE, DEVANAGARI, JAPANESE, KOREAN }
    // Google's published Supported + Experimental table, checked 2026-10-12.
    // Unknown languages and explicit incompatible scripts must not fall back to Latin.
    private val latin = setOf("af", "sq", "ca", "hr", "cs", "da", "nl", "en", "et", "fil", "tl",
        "fi", "fr", "de", "hu", "is", "id", "it", "lv", "lt", "ms", "no", "nb", "pl", "pt",
        "ro", "sk", "sl", "es", "sv", "tr", "vi", "az", "eu", "bs", "ceb", "eo", "gl", "ht",
        "ga", "jv", "la", "mt", "sw", "uz", "cy", "zu")
    fun mlKitScript(language: String): Script? {
        val parts = language.replace('_', '-').lowercase(java.util.Locale.ROOT).split('-')
        val base = parts.first()
        val script = parts.drop(1).firstOrNull { it.length == 4 }
        return when {
            base in latin && (script == null || script == "latn") -> Script.LATIN
            base == "sr" && script == "latn" -> Script.LATIN
            base == "zh" && (script == null || script in setOf("hans", "hant")) -> Script.CHINESE
            base == "ja" && (script == null || script == "jpan") -> Script.JAPANESE
            base == "ko" && (script == null || script == "kore") -> Script.KOREAN
            base in setOf("hi", "mr", "ne", "sa") && (script == null || script == "deva") -> Script.DEVANAGARI
            else -> null
        }
    }
}
