package org.openoffline.translator.inference
import org.junit.Assert.*
import org.junit.Test
class IndexContractTest {
    @Test fun unicodeIsStandardUtf8() {
        val text = "Привет 👋 ไทย e\u0301 <|im_end|>"
        assertEquals(text, String(IndexRequest.utf8(text), Charsets.UTF_8))
        assertTrue(IndexRequest.utf8("👋").contentEquals(byteArrayOf(0xf0.toByte(),0x9f.toByte(),0x91.toByte(),0x8b.toByte())))
    }
    @Test fun nulAndUnpairedSurrogatesAreRejected() {
        for (text in listOf("before\u0000after", "\uD800", "\uDC00")) {
            assertThrows(IllegalArgumentException::class.java) { IndexRequest.utf8(text) }
        }
    }
    @Test fun promptMatchesApple() {
        assertEquals("<|im_start|>user\n请将以下文本翻译为英语，直接输出翻译结果，不要进行任何解释。\n\n", IndexRequest("x", "en").prefix)
        assertEquals("<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n", IndexRequest("x", "ru").suffix)
    }
    @Test fun preflightKeepsOutputRoomWithoutOverflow() {
        assertTrue(IndexRequest.fits(811, 781))
        assertFalse(IndexRequest.fits(812, 782))
        assertFalse(IndexRequest.fits(1537, 10))
        assertFalse(IndexRequest.fits(-1, 10))
        assertFalse(IndexRequest.fits(10, Int.MAX_VALUE))
    }
}
