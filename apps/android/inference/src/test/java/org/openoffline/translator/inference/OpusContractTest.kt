package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test

class OpusContractTest {
    @Test fun segmentationPreservesParagraphsUnicodeAndEveryCharacter() {
        val text = "Привет 👩🏽‍💻! Следующее предложение.\n\nІ ще одне беларускае: Ўсім прывітанне. " + "Длинный текст ".repeat(80)
        val parts = OpusSegments.split(text) { it.codePointCount(0, it.length) <= 35 }
        assertEquals(text, parts.joinToString(""))
        assertTrue(parts.size > 2)
        assertTrue(parts.all { it.codePointCount(0, it.length) <= 35 })
        parts.forEach { IndexRequest.utf8(it) }
    }
    @Test fun nonFittingSingleCharacterFailsInsteadOfDroppingSource() {
        try { OpusSegments.split("字") { false }; fail("Expected finite-context error") }
        catch (_: IllegalArgumentException) { }
    }
}
