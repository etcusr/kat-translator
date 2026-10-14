package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.compose.setContent
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.openoffline.translator.android.packages.*
import org.openoffline.translator.inference.OfflineMedia
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RecognitionRoutingFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=inst.targetContext
    private fun fixture(language:String):File=File.createTempFile("routing-$language-",".wav",context.cacheDir).apply {
        inst.context.assets.open("media-asr-$language.fixture").use { input -> outputStream().use { input.copyTo(it) } }
    }
    private fun report(text:String)=inst.sendStatus(0,Bundle().apply { putString("stream","\nASR_ROUTING $text\n") })
    @Test fun autoSwitchesEnglishRussianEnglishThroughProduct() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false);state.changeAutomaticSpeech(false)
            state.changeRecognitionPreference("automatic");state.selectTranslation("opus")
        }
        ui.waitUntil(30000) { state.packages.restored.value }
        for(language in listOf("en","ru","en")) {
            val file=fixture(language)
            try {
                ui.runOnIdle {
                    state.mode="text";state.chooseLanguage(language,true);state.chooseLanguage(if(language=="en")"ru" else "en",false);state.mode="voice"
                    assertEquals(if(language=="en")"parakeet" else "gigaam",state.automaticRecognitionPackage!!.backend)
                }
                val start=SystemClock.elapsedRealtime()
                ui.runOnUiThread { state.importAudio(Uri.fromFile(file)) }
                ui.waitUntil(45000) { !state.busy }
                ui.runOnIdle {
                    assertNull(state.error);assertEquals(if(language=="en")"parakeet" else "gigaam",state.recognitionBackend)
                    assertEquals(language,state.detectedSource)
                    if(language=="en")assertTrue(state.input,state.input.contains("not cancel",true) && state.input.contains("train",true))
                    else assertTrue(state.input,state.input.contains("здравствуйте",true) && state.input.contains("часов",true))
                    assertTrue(state.output.isNotBlank());assertTrue(state.hasOriginalAudio)
                    report("language=$language backend=${state.recognitionBackend} asr=${state.timing?.recognition} totalMs=${SystemClock.elapsedRealtime()-start}")
                }
            } finally { file.delete() }
        }
        ui.runOnIdle {
            state.changeRecognitionPreference("system");assertNull(state.automaticRecognitionPackage)
            state.changeRecognitionPreference("whisper");assertNull(state.automaticRecognitionPackage)
        }
    }
    @Test fun parakeetRetainsAllPhrasesAndCanCancelThenReuse() {
        val file=fixture("en")
        try {
            val samples=AudioImport.decode(context,Uri.fromFile(file)){false}
            val dir=File(context.getExternalFilesDir(null),"packages/parakeet-v3-int8").path
            val vad=File(context.noBackupFilesDir,"silero_vad.onnx")
            if(!vad.isFile)context.assets.open("silero_vad.onnx").use { input -> vad.outputStream().use { input.copyTo(it) } }
            val long=(1..8).fold(FloatArray(0)) { a,_ -> a+samples+FloatArray(16000) }
            OfflineMedia().use { media ->
                val result=media.transcribeParakeet(dir,long,vad.path,"en")
                assertEquals(result.text,8,Regex("train",RegexOption.IGNORE_CASE).findAll(result.text).count())
                assertEquals(result.text,8,Regex("not cancel",RegexOption.IGNORE_CASE).findAll(result.text).count())
                val timer=Executors.newSingleThreadScheduledExecutor()
                try {
                    val start=SystemClock.elapsedRealtime()
                    val cancel=timer.schedule({media.cancel()},250,TimeUnit.MILLISECONDS)
                    try { media.transcribeParakeet(dir,(1..6).fold(FloatArray(0)){a,_->a+samples},vad.path,"en");fail("Cancellation must not return text") }
                    catch(_:CancellationException) { report("parakeetCancelMs=${SystemClock.elapsedRealtime()-start}");assertTrue(SystemClock.elapsedRealtime()-start<4000) }
                    finally { cancel.cancel(false) }
                    assertTrue(media.transcribeParakeet(dir,samples,vad.path,"en").text.contains("not cancel",true))
                } finally { timer.shutdownNow() }
            }
        } finally { file.delete() }
    }
    @Test fun missingModelNoticeOffersDownloadAndShowsProgress() {
        val status=mutableStateOf(PackageStatus());var clicks=0
        ui.activity.runOnUiThread { ui.activity.setContent { RecognitionDownloadNotice("Parakeet TDT v3",status.value) { clicks++ } } }
        ui.onNodeWithTag("recognition.download.notice").assertIsDisplayed().performClick()
        ui.runOnIdle { assertEquals(1,clicks);status.value=PackageStatus(PackagePhase.DOWNLOADING,50,100) }
        ui.onNodeWithTag("recognition.download.notice").assertTextContains("50%",substring=true).assertIsNotEnabled()
    }
    @Test fun parakeetCanBeSelectedFromModelsScreen() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
        ui.waitUntil(30000) { state.packages.restored.value }
        ui.onNodeWithTag("toolbar.models").performClick()
        val tag="recognition.parakeet-v3-int8.select"
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag(tag))
        ui.onNodeWithTag(tag).performClick()
        ui.runOnIdle { assertEquals("parakeet-v3-int8",state.selectedRecognition()) }
    }
}
