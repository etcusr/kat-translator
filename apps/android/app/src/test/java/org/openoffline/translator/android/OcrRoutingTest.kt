package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test

class OcrRoutingTest {
    @Test fun supportedLanguagesSelectTheirActualScript() {
        listOf("en", "en-GB", "fr-CA", "de", "vi", "tr", "fil", "tl", "sr-Latn", "pt-BR").forEach {
            assertEquals(it, OcrRouting.Script.LATIN, OcrRouting.mlKitScript(it))
        }
        assertEquals(OcrRouting.Script.CHINESE, OcrRouting.mlKitScript("zh-Hant-TW"))
        assertEquals(OcrRouting.Script.JAPANESE, OcrRouting.mlKitScript("ja"))
        assertEquals(OcrRouting.Script.KOREAN, OcrRouting.mlKitScript("ko"))
        listOf("hi", "mr", "ne").forEach { assertEquals(OcrRouting.Script.DEVANAGARI, OcrRouting.mlKitScript(it)) }
    }
    @Test fun unknownAndUnsupportedScriptsNeverSilentlyBecomeLatin() {
        listOf("auto", "ru", "uk", "be", "sr", "sr-Cyrl", "en-Cyrl", "az-Arab", "th", "ar", "el", "xx", "").forEach {
            assertNull(it, OcrRouting.mlKitScript(it))
        }
    }
    @Test fun languageTagsAreCaseInsensitiveAndAcceptAndroidSeparators() {
        assertEquals(OcrRouting.Script.LATIN, OcrRouting.mlKitScript("EN_us"))
        assertEquals(OcrRouting.Script.LATIN, OcrRouting.mlKitScript("SR_latn_RS"))
    }
}
