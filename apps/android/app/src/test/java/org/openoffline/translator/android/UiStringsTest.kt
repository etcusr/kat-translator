package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test
import org.openoffline.translator.android.packages.PackageMessages

class UiStringsTest {
    @Test fun selectedLanguageAndSystemFallback() {
        assertEquals("es", UiStrings.language("es", listOf("ru-RU")))
        assertEquals("tr", UiStrings.language("system", listOf("tr-TR", "en-US")))
        assertEquals("es", UiStrings.language("system", listOf("fr-FR", "es_ES")))
        assertEquals("en", UiStrings.language("system", listOf("sr-Latn-ME")))
        assertEquals("ru", UiStrings.language("invalid", listOf("ru-RU")))
        assertEquals("en", UiStrings.language(null, emptyList()))
    }
    @Test fun settingsAndMessagesUseSelectedDictionary() {
        assertEquals("Ajustes", UiStrings.text("Настройки", language="es"))
        assertEquals("Ayarlar", UiStrings.text("Настройки", language="tr"))
        assertEquals("Descargado y verificado", UiStrings.text("Скачано и проверено", language="es"))
        assertEquals("Konuşma tanıma paketi indirilemedi. İndirmeye devam edebilirsiniz.", UiStrings.text("Не удалось скачать пакет распознавания. Можно продолжить загрузку.", language="tr"))
    }
    @Test fun interpolationPreservesUserDataAndPercentSigns() {
        assertEquals("Caracteres: 17", UiStrings.text("Символов: %@", null, "es", 17))
        assertEquals("%@ 100% indirilemedi. Yeniden denemek için dokunun.", UiStrings.text("Не удалось скачать %@. Нажмите, чтобы повторить.", null, "tr", "%@ 100%"))
        assertEquals("Seslendirme indiriliyor: test · 50%", UiStrings.text("unknown", "Seslendirme indiriliyor: %@ · %@%", "tr", "test", 50))
    }
    @Test fun downloadErrorsAndLanguageNamesAreLocalized() {
        assertEquals("El servidor ha devuelto HTTP 403", PackageMessages.display("Сервер вернул HTTP 403", "es"))
        assertEquals("Boş alan yetersiz. 120 MB daha gerekiyor", PackageMessages.display("Недостаточно свободного места. Нужно ещё 120 МБ", "tr"))
        assertEquals("español", UiStrings.languageName("es", "Испанский", "Spanish", "es"))
        assertEquals("Türkçe", UiStrings.languageName("tr", "Турецкий", "Turkish", "tr"))
        assertEquals("native error 42", PackageMessages.display("native error 42", "tr"))
    }
}
