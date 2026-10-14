package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.openoffline.translator.inference.OfflineMedia
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GigaSpeechTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=inst.targetContext
    private val model get()=File(context.getExternalFilesDir(null),"packages/gigaam-v3-int8").path
    private fun vad():String {
        val file=File(context.noBackupFilesDir,"silero_vad.onnx")
        if(!file.isFile)context.assets.open("silero_vad.onnx").use { input -> file.outputStream().use { input.copyTo(it) } }
        return file.path
    }
    private fun fixture():FloatArray {
        val file=File.createTempFile("giga-test-",".wav",context.cacheDir)
        try {
            inst.context.assets.open("media-asr-ru.fixture").use { input -> file.outputStream().use { input.copyTo(it) } }
            return AudioImport.decode(context,Uri.fromFile(file)){false}
        } finally { file.delete() }
    }
    private fun report(value:String)=inst.sendStatus(0,Bundle().apply { putString("stream","\nGIGA $value\n") })
    @Test fun longRecordingKeepsEveryRepeatedSentence() {
        val phrase=fixture();val pause=FloatArray(16000)
        val long=(1..6).fold(FloatArray(0)) { acc,_ -> acc+phrase+pause }
        OfflineMedia().use { media ->
            val start=SystemClock.elapsedRealtime();val result=media.transcribeGigaAM(model,long,vad())
            report("long audio=${long.size/16000.0} seconds=${(SystemClock.elapsedRealtime()-start)/1000.0} text=${result.text}")
            // Completeness is separate from WER: this model spells поезд as поест in the
            // repeated synthetic clip. Keep raw output visible; do not disguise it as exact parity.
            for(marker in listOf("здравствуйте","отправляется","часов"))
                assertEquals(result.text,6,Regex(marker,RegexOption.IGNORE_CASE).findAll(result.text).count())
        }
    }
    @Test fun cancelThenReuseAndSilence() {
        val phrase=fixture();val timer=Executors.newSingleThreadScheduledExecutor()
        try { OfflineMedia().use { media ->
            assertTrue(media.transcribeGigaAM(model,phrase,vad()).text.contains("поезд"))
            val long=(1..4).fold(FloatArray(0)) { acc,_ -> acc+phrase }
            val start=SystemClock.elapsedRealtime();val task=timer.schedule({media.cancel()},250,TimeUnit.MILLISECONDS)
            try { media.transcribeGigaAM(model,long,vad());fail("Cancelled ASR must not publish partial text") }
            catch(_:CancellationException) { report("cancelMillis=${SystemClock.elapsedRealtime()-start}");assertTrue(SystemClock.elapsedRealtime()-start<3000) }
            finally { task.cancel(false) }
            assertTrue(media.transcribeGigaAM(model,phrase,vad()).text.contains("поезд"))
            try { media.transcribeGigaAM(model,FloatArray(16000*5),vad());fail("Silence must not hallucinate") }
            catch(e:IllegalStateException) { assertEquals("No speech detected",e.message) }
        } } finally { timer.shutdownNow() }
    }
    @Test fun modelCanBeSelectedFromModelsScreen() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
        ui.waitUntil(30000) { state.packages.restored.value }
        ui.onNodeWithTag("toolbar.models").performClick()
        val tag="recognition.gigaam-v3-int8.select"
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag(tag))
        ui.onNodeWithTag(tag).performClick()
        ui.runOnIdle { assertEquals("gigaam-v3-int8",state.selectedRecognition()) }
        ui.onNodeWithTag(tag).assertIsNotEnabled()
    }
    /** Opt-in private recording in cache; never bundled or copied into durable test fixtures. */
    @Test fun suppliedRecordingCompletesThroughProduct() {
        val file=File(context.cacheDir,"asr-completeness.wav")
        org.junit.Assume.assumeTrue("Diagnostic recording was not supplied",file.isFile)
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false);state.changeAutomaticSpeech(false)
            state.changeRecognitionPreference("automatic");state.selectTranslation("opus")
            state.mode="text";state.chooseLanguage("ru",true);state.chooseLanguage("en",false);state.mode="voice"
        }
        ui.waitUntil(30000) { state.packages.restored.value }
        val start=SystemClock.elapsedRealtime()
        ui.runOnUiThread { state.importAudio(Uri.fromFile(file)) }
        ui.waitUntil(45000) { !state.busy }
        ui.runOnIdle {
            assertNull(state.error);assertEquals("gigaam",state.recognitionBackend)
            assertTrue(state.input,state.input.contains("озвучки") && state.input.contains("распознавания"))
            assertTrue(state.output,state.output.contains("recognition",true))
            assertTrue(state.hasOriginalAudio)
            // Do not put private transcript into persistent test logs.
            report("productMillis=${SystemClock.elapsedRealtime()-start} asrSeconds=${state.timing?.recognition} mtSeconds=${state.timing?.translation} originalChars=${state.input.length} translationChars=${state.output.length}")
        }
    }
}
