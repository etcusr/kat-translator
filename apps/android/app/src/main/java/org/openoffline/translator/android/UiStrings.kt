package org.openoffline.translator.android

import java.util.Locale

/** UI templates only. User text and model prompts never enter the dictionaries. */
object UiStrings {
    val supportedLanguages = setOf("ru", "en", "es", "tr")
    fun language(preference: String?, systemLanguages: List<String>): String {
        if (preference in supportedLanguages) return preference!!
        return systemLanguages.asSequence().map { it.replace('_', '-').substringBefore('-').lowercase(Locale.ROOT) }
            .firstOrNull { it in supportedLanguages } ?: "en"
    }
    fun dictionary(language: String): Map<String, String> = when (language) {
        "es" -> UiStringsEs.values
        "tr" -> UiStringsTr.values
        else -> UiStringsEn.values
    }
    fun text(ru: String, en: String? = null, language: String, vararg arguments: Any?): String {
        val template = if (language == "ru") ru else dictionary(language)[ru] ?: en ?: UiStringsEn.values[ru] ?: ru
        if (arguments.isEmpty()) return template
        var index = 0
        // A single pass preserves literal placeholder-like text inside user arguments.
        return Regex("%@").replace(template) { arguments.getOrNull(index++)?.toString().orEmpty() }
    }
    fun languageName(id: String, russian: String, english: String, language: String): String = when(language) {
        "ru" -> russian
        "en" -> english
        else -> Locale.forLanguageTag(id).getDisplayLanguage(Locale.forLanguageTag(language)).takeIf { it.isNotBlank() && it != id } ?: english
    }
}
