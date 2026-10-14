package org.openoffline.translator.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
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

/** Generated public text, installed shared OCR weights only. No translation, camera,
 * network, preferences, history, fixture imports, or model deletion. Root runs alone. */
@RunWith(AndroidJUnit4::class)
class AutoOcrDeviceTest {
    @Test fun ambiguousMonospaceRequiresExplicitSourceAndManualEslavRecognizesIt() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        val repository=PackageDownloads.repository(context)
        runBlocking { withTimeout(180_000) { repository.restored.first { it } } }
        val ids=listOf("ppocr-v5-det",OcrAutoSelection.ENGLISH,OcrAutoSelection.ESLAV)
        ids.forEach { assertNotNull("Install exact shared OCR fixture $it",repository.installedPath(it)) }
        val leases=ids.map { repository.acquire(it) }
        val bitmap=Bitmap.createBitmap(1000,300,Bitmap.Config.ARGB_8888)
        try {
            val detector=requireNotNull(repository.installedPath(ids.first())).path
            val models=ids.drop(1).map { id ->
                val dictionary=if(id==OcrAutoSelection.ENGLISH)"ocr-english-characters.json" else "ocr-eslav-characters.json"
                val chars=JSONArray(context.assets.open(dictionary).bufferedReader().use { it.readText() })
                OcrRecognizer(id,requireNotNull(repository.installedPath(id)).path,(0 until chars.length()).map { chars.getString(it) })
            }
            Canvas(bitmap).apply {
                drawColor(Color.WHITE)
                drawText("Встреча завтра",60f,140f,Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color=Color.BLACK;textSize=54f;typeface=Typeface.MONOSPACE
                })
            }
            OfflineMedia().use { media ->
                val ambiguity=assertThrows(OcrAutoSelection.Ambiguous::class.java) {
                    media.recognizeAuto(bitmap,detector,models)
                }
                assertEquals(OcrAutoSelection.requiredModels,ambiguity.candidates.map { it.modelId }.toSet())
                instrumentation.sendStatus(0,Bundle().apply {
                    putString("stream","\nAUTO OCR expected ambiguity: ${ambiguity.candidates}\n")
                })
                val explicit=models.single { it.modelId==OcrAutoSelection.ESLAV }
                val blocks=media.recognize(bitmap,detector,explicit.path,explicit.dictionary)
                val text=blocks.joinToString(" ") { it.text }.trim().replace(Regex("\\s+")," ")
                assertEquals("Explicit Cyrillic must resolve the same image","встреча завтра",text.lowercase())
                assertTrue(blocks.isNotEmpty())
                blocks.forEach {
                    assertTrue(it.left>=0f && it.top>=0f && it.right<=1f && it.bottom<=1f)
                    assertTrue(it.right>it.left && it.bottom>it.top)
                }
                instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nEXPLICIT CYRILLIC OCR: $text\n") })
            }
        } finally { bitmap.recycle();leases.asReversed().forEach { it.close() } }
    }

    @Test fun realEnglishCyrillicAndMixedPageUseInstalledRecognizerEvidence() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        val repository=PackageDownloads.repository(context)
        runBlocking { withTimeout(180_000) { repository.restored.first { it } } }
        val ids=listOf("ppocr-v5-det",OcrAutoSelection.ENGLISH,OcrAutoSelection.ESLAV)
        ids.forEach { assertNotNull("Install exact shared OCR fixture $it",repository.installedPath(it)) }
        val leases=ids.map { repository.acquire(it) }
        try {
            val detector=requireNotNull(repository.installedPath(ids.first())).path
            val models=ids.drop(1).map { id ->
                val dictionary=if(id==OcrAutoSelection.ENGLISH)"ocr-english-characters.json" else "ocr-eslav-characters.json"
                val chars=JSONArray(context.assets.open(dictionary).bufferedReader().use { it.readText() })
                OcrRecognizer(id,requireNotNull(repository.installedPath(id)).path,(0 until chars.length()).map { chars.getString(it) })
            }
            OfflineMedia().use { media ->
                fun check(lines:List<String>, choices:List<OcrRecognizer>, font:Typeface=Typeface.DEFAULT, size:Float=72f) {
                    val bitmap=Bitmap.createBitmap(1000,lines.size*180+120,Bitmap.Config.ARGB_8888)
                    try {
                        val canvas=Canvas(bitmap);canvas.drawColor(Color.WHITE)
                        val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=size;typeface=font }
                        lines.forEachIndexed { i,line -> canvas.drawText(line,60f,140f+i*180f,paint) }
                        val blocks=try { media.recognizeAuto(bitmap,detector,choices) }
                        catch(e:OcrAutoSelection.Ambiguous) { throw AssertionError("Generated OCR candidates: ${e.candidates}",e) }
                        val recognized=blocks.joinToString(" ") { it.text }.uppercase()
                        instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nAUTO OCR ${choices.map { it.modelId }}: $recognized\n") })
                        for(line in lines)for(word in line.split(" "))assertTrue("Missing $word in $recognized",recognized.contains(word.uppercase()))
                        assertTrue(blocks.isNotEmpty())
                        blocks.forEach {
                            assertTrue(it.left>=0f && it.top>=0f && it.right<=1f && it.bottom<=1f)
                            assertTrue(it.right>it.left && it.bottom>it.top)
                        }
                        if(lines==listOf("HELLO WORLD"))assertFalse(recognized.any { it in '\u0400'..'\u04ff' })
                        if(lines==listOf("ПРИВЕТ МИР"))assertFalse(recognized.any { it in 'A'..'Z' })
                    } finally { bitmap.recycle() }
                }
                val failures=mutableListOf<String>()
                fun sample(label:String, action:()->Unit) {
                    try { action() } catch(e:AssertionError) { failures+="$label: ${e.message}" }
                    instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nAUTO OCR sample: $label; failures=${failures.size}\n") })
                }
                sample("single English") { check(listOf("HELLO WORLD"),models.filter { it.modelId==OcrAutoSelection.ENGLISH }) }
                sample("dual English") { check(listOf("HELLO WORLD"),models) }
                sample("dual Cyrillic") { check(listOf("ПРИВЕТ МИР"),models) }
                sample("mixed reversed order") { check(listOf("HELLO WORLD","ПРИВЕТ МИР"),models.reversed()) }
                sample("English serif lowercase") { check(listOf("hello world"),models,Typeface.SERIF,60f) }
                sample("Cyrillic serif lowercase") { check(listOf("привет мир"),models,Typeface.SERIF,60f) }
                sample("English monospace") { check(listOf("Meeting tomorrow"),models,Typeface.MONOSPACE,54f) }
                assertTrue(failures.joinToString("\n"),failures.isEmpty())
            }
        } finally { leases.asReversed().forEach { it.close() } }
    }
}
