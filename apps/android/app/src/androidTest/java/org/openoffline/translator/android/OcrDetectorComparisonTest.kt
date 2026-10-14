package org.openoffline.translator.android

import android.graphics.*
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageDownloads
import org.openoffline.translator.inference.*
import java.io.File
import java.security.MessageDigest

/** Same complete OCR path, same recognition weights/crops policy; only detector varies.
 * No production installs, preferences or user photos are changed. */
@RunWith(AndroidJUnit4::class)
class OcrDetectorComparisonTest {
    @Test fun mobileAndServerRecognizeSamePublicCorpus() {
        val inst=InstrumentationRegistry.getInstrumentation();val ctx=inst.targetContext
        val repo=PackageDownloads.repository(ctx)
        runBlocking { withTimeout(60_000) { repo.restored.first { it } } }
        val mobile=File(ctx.noBackupFilesDir,"ocr-research/mobile.onnx")
        assertEquals("4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae",MessageDigest.getInstance("SHA-256").digest(mobile.readBytes()).joinToString("") { "%02x".format(it) })
        val ids=listOf("ppocr-v5-det","ppocr-v5-eslav","ppocr-v5-english")
        val leases=ids.map { repo.acquire(it) }
        try {
            val models=ids.drop(1).associateWith { id ->
                val dictionary=if(id.endsWith("eslav"))"ocr-eslav-characters.json" else "ocr-english-characters.json"
                val chars=JSONArray(ctx.assets.open(dictionary).bufferedReader().use { it.readText() })
                OcrRecognizer(id,requireNotNull(repo.installedPath(id)).path,(0 until chars.length()).map { chars.getString(it) })
            }
            val corpus=listOf(Triple("ru",listOf("ПРИВЕТ МИР"),Typeface.DEFAULT),Triple("ru",listOf("Встреча завтра в 15:30"),Typeface.SERIF),Triple("ru",listOf("Цена 1250 рублей","Поезд отправляется завтра"),Typeface.DEFAULT),Triple("en",listOf("Meeting tomorrow 15:30"),Typeface.MONOSPACE),Triple("ru",listOf("Магазин открыт до 20:00","Стоимость билета 250 рублей"),Typeface.DEFAULT))
            val failures=mutableListOf<String>()
            OfflineMedia().use { media ->
                for((sample,c) in corpus.withIndex()) {
                    val (language,lines,font)=c
                    val bitmap=Bitmap.createBitmap(1200,lines.size*150+120,Bitmap.Config.ARGB_8888)
                    try {
                        Canvas(bitmap).apply {
                            drawColor(Color.WHITE)
                            val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=if(sample==4)34f else 60f;typeface=font }
                            lines.forEachIndexed { i,line -> drawText(line,45f,130f+i*150f,paint) }
                        }
                        repeat(3) { pass ->
                            val detectors=listOf("server" to requireNotNull(repo.installedPath("ppocr-v5-det")).path,"mobile" to mobile.path).let { if(pass%2==0)it else it.reversed() }
                            for((label,detector) in detectors) {
                                val started=SystemClock.elapsedRealtime()
                                try {
                                    val blocks=if(language=="auto")media.recognizeAuto(bitmap,detector,models.values.toList()) else {
                                        val model=models.getValue(if(language=="ru")"ppocr-v5-eslav" else "ppocr-v5-english")
                                        media.recognize(bitmap,detector,model.path,model.dictionary)
                                    }
                                    val actual=blocks.joinToString(" ") { it.text }
                                    fun normalize(s:String)=s.lowercase().filter { it.isLetterOrDigit() }
                                    if(normalize(actual)!=normalize(lines.joinToString(" ")))failures+="$label case=$sample: $actual"
                                    inst.sendStatus(0,Bundle().apply { putString("stream","\nOCR_DETECTOR $label case=$sample pass=$pass total=${SystemClock.elapsedRealtime()-started}ms text=$actual\n") })
                                } catch(e:Exception) { failures+="$label case=$sample: $e" }
                            }
                        }
                    } finally { bitmap.recycle() }
                }
            }
            assertTrue(failures.joinToString("\n"),failures.isEmpty())
        } finally { leases.asReversed().forEach { it.close() } }
    }
}
