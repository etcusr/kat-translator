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

/** The real Cancel button must interrupt Whisper's encoder, not wait for its result. */
@RunWith(AndroidJUnit4::class)
class SpeechCancellationTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private lateinit var state:TranslatorState

    @Test fun cancelActiveRecognitionThenUseTranslatorAgain() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val fixture=File(instrumentation.targetContext.cacheDir,"cancel-asr-fixture.wav")
        instrumentation.context.assets.open("media-asr-en.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        try {
            ui.runOnIdle {
                state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
                state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
                state.changeAutomaticSpeech(false);state.changeRecognitionPreference("whisper")
                state.selectRecognition("whisper-large-v3-turbo-f16")
                state.selectTranslation("opus");state.chooseLanguage("en",true);state.chooseLanguage("ru",false)
            }
            ui.waitUntil(30_000) { state.packages.restored.value }
            ui.runOnUiThread { state.importAudio(Uri.fromFile(fixture)) }
            ui.waitUntil(10_000) { state.hasOriginalAudio && state.busy }
            // Let model initialization finish so cancellation exercises active compute.
            // The optimized large-v3-turbo still needs more than five seconds here.
            SystemClock.sleep(5_000)
            ui.runOnIdle { assertTrue(state.busy);assertEquals("whisper",state.recognitionBackend);assertEquals("",state.input) }
            val started=SystemClock.elapsedRealtime()
            ui.onNodeWithTag("processing.cancel").performScrollTo().performClick()
            ui.waitUntil(8_000) { !state.busy }
            val elapsed=SystemClock.elapsedRealtime()-started
            ui.runOnIdle {
                assertNull(state.error);assertEquals("",state.input);assertEquals("",state.output)
                state.mode="text";state.input="The train leaves tomorrow at 10:30."
            }
            ui.onNodeWithTag("processing.overlay").assertDoesNotExist()
            ui.onNodeWithTag("text.translate").assertIsDisplayed().performClick()
            ui.waitUntil(60_000) { !state.busy }
            ui.runOnIdle { assertNull(state.error);assertTrue(state.output,state.output.contains("завтра",true)) }
            instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nASR cancel-to-idle=${elapsed}ms; no partial text; subsequent OPUS completed\n") })
        } finally {
            if(::state.isInitialized)ui.runOnUiThread { state.cancel() }
            fixture.delete()
        }
    }
}
