package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Real product path: the same saved recording flows through system ASR and OPUS. */
@RunWith(AndroidJUnit4::class)
class SystemVoiceFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun explicitSystemSpeechShowsCompletedTranslation()=run("ru")
    @Test fun legacyAutoSelectionUsesExplicitLanguageWithoutDetectionPass()=run("auto")

    private fun run(source:String) {
        val inst=InstrumentationRegistry.getInstrumentation()
        val fixture=File(inst.targetContext.cacheDir,"system-voice-flow.wav")
        inst.context.assets.open("media-asr-ru.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        lateinit var state:TranslatorState
        try {
            ui.runOnIdle {
                state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
                state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
                state.changeAutomaticSpeech(false);state.changeRecognitionPreference("system")
                state.selectTranslation("opus");state.mode="text";state.chooseLanguage("en",false);state.chooseLanguage("ru",true);state.chooseLanguage(source,true);state.mode="voice"
                assertEquals("ru",state.currentSource)
            }
            ui.waitUntil(30_000) { state.packages.restored.value }
            val started=SystemClock.elapsedRealtime()
            ui.runOnUiThread { state.importAudio(Uri.fromFile(fixture)) }
            ui.waitUntil(25_000) { !state.busy }
            ui.runOnIdle {
                assertNull(state.error);assertEquals("android",state.recognitionBackend)
                assertEquals("ru",state.detectedSource)
                assertTrue("The beginning must survive language detection: ${state.input}",state.input.contains("здравствуйте",true))
                assertTrue(state.input,state.input.contains("поезд",true))
                assertTrue(state.output,state.output.contains("train",true))
                assertTrue(state.hasOriginalAudio);assertFalse(state.ready)
            }
            ui.onNodeWithTag("text.translation.text").performScrollTo().assertIsDisplayed()
            inst.sendStatus(0,Bundle().apply { putString("stream","\nSYSTEM_VOICE source=$source completeASR+OPUS=${SystemClock.elapsedRealtime()-started}ms input=${state.input} output=${state.output}\n") })
        } finally { fixture.delete() }
    }
}
