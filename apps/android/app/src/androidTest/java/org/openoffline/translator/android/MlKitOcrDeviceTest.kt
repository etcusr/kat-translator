package org.openoffline.translator.android

import android.graphics.*
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.*

@RunWith(AndroidJUnit4::class)
class MlKitOcrDeviceTest {
    private fun bitmap(text: String) = Bitmap.createBitmap(1200, 300, Bitmap.Config.ARGB_8888).apply {
        Canvas(this).apply {
            drawColor(Color.WHITE)
            drawText(text, 55f, 160f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK; textSize=66f })
        }
    }
    @Test fun fiveBundledScriptsRecognizeTextAndNormalizedGeometry() {
        val ocr=MlKitOcr()
        val samples=listOf("en" to "Meeting tomorrow 15:30", "fr" to "Bonjour le monde", "zh" to "你好世界", "ja" to "こんにちは世界", "ko" to "안녕하세요 세계", "hi" to "नमस्ते दुनिया")
        try { for((language,text) in samples) {
            val image=bitmap(text)
            try {
                repeat(3) { run ->
                    val start=SystemClock.elapsedRealtime()
                    val blocks=ocr.recognize(image,requireNotNull(OcrRouting.mlKitScript(language)))
                    val result=blocks.joinToString(" ") { it.text }
                    fun normalize(s:String)=s.filterNot { it.isWhitespace() }.lowercase()
                    assertEquals("$language pass $run",normalize(text),normalize(result))
                    assertTrue(blocks.isNotEmpty())
                    blocks.forEach { assertTrue(it.left>=0 && it.top>=0 && it.right<=1 && it.bottom<=1 && it.right>it.left && it.bottom>it.top) }
                    InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply {
                        putString("stream","\nMLKIT $language pass=$run total=${SystemClock.elapsedRealtime()-start}ms text=$result\n")
                    })
                }
            } finally { image.recycle() }
        } } finally { ocr.close() }
    }
    @Test fun cancelledRequestCannotPublishAndNextRequestWorks() {
        val ocr=MlKitOcr();val image=bitmap("HELLO WORLD")
        val entered=CountDownLatch(1);val executor=Executors.newSingleThreadExecutor()
        try {
            assertThrows(CancellationException::class.java) { ocr.recognize(image,OcrRouting.Script.LATIN) { true } }
            val future=executor.submit<List<org.openoffline.translator.inference.OcrBlock>> {
                ocr.recognize(image,OcrRouting.Script.LATIN) { entered.countDown(); false }
            }
            assertTrue(entered.await(2,TimeUnit.SECONDS));ocr.cancel()
            val error=assertThrows(ExecutionException::class.java) { future.get(3,TimeUnit.SECONDS) }
            assertTrue(error.cause.toString(),error.cause is CancellationException)
            assertEquals("HELLO WORLD",ocr.recognize(image,OcrRouting.Script.LATIN).joinToString(" ") { it.text })
        } finally { executor.shutdownNow();ocr.close();image.recycle() }
    }
    @Test fun emptyImageReturnsNoInventedText() {
        val image=Bitmap.createBitmap(600,300,Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
        try { MlKitOcr().use { assertTrue(it.recognize(image,OcrRouting.Script.LATIN).isEmpty()) } } finally { image.recycle() }
    }
}
