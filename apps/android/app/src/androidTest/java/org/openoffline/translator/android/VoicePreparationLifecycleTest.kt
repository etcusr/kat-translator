package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Actual installed models; no recording, translation, history or screen-policy changes. */
class VoicePreparationLifecycleTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private lateinit var state:TranslatorState
    private fun setup(recognizer:String="whisper-large-v3-turbo-q8_0") {
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
        ui.waitUntil(30_000) { state.packages.restored.value && !state.busy }
        ui.runOnIdle {
            state.selectTranslation("opus");state.changeMemorySaving(false)
            state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
            state.selectRecognition(recognizer);state.mode="voice"
        }
        ui.waitUntil(10_000) { !state.modelReady && state.recognitionRuntime==null }
    }
    @Test fun whisperPreparedBeforeMicAndReloadedAcrossTextCameraAndPressure() {
        setup()
        ui.onNodeWithTag("voice.record").assertDoesNotExist()
        ui.onNodeWithTag("voice.prepare").performClick()
        ui.waitUntil(90_000) { !state.busy }
        var loads=0;var translationLoads=0
        ui.runOnIdle {
            assertNull(state.error);assertTrue(state.voiceReady);assertEquals("i8mm",state.recognitionRuntime)
            loads=state.recognitionLoads;translationLoads=state.opusLoadCount
        }
        ui.onNodeWithTag("voice.record").assertExists()
        ui.onNodeWithTag("mode.text").performClick()
        ui.waitUntil(20_000) { state.recognitionRuntime==null }
        ui.runOnIdle { assertFalse(state.recognitionReady);assertTrue(state.modelReady);assertEquals(translationLoads,state.opusLoadCount) }
        ui.onNodeWithTag("mode.voice").performClick()
        ui.waitUntil(60_000) { !state.busy && state.voiceReady }
        ui.runOnIdle { assertEquals(loads+1,state.recognitionLoads);assertEquals(translationLoads,state.opusLoadCount);state.mode="camera" }
        ui.waitUntil(20_000) { state.recognitionRuntime==null }
        ui.runOnIdle { assertFalse(state.recognitionReady);assertTrue(state.modelReady);state.mode="voice" }
        ui.waitUntil(60_000) { !state.busy && state.voiceReady }
        ui.runOnIdle { assertEquals(loads+2,state.recognitionLoads);state.trimMemory() }
        ui.waitUntil(20_000) { state.recognitionRuntime==null }
        ui.onNodeWithTag("voice.record").assertDoesNotExist()
        ui.runOnIdle {
            assertTrue(state.modelReady);assertFalse(state.recognitionReady);assertEquals(translationLoads,state.opusLoadCount)
            state.prepare();state.mode="text";state.mode="voice"
            assertFalse(state.voiceReady)
        }
        ui.waitUntil(90_000) { !state.busy && state.voiceReady }
        ui.runOnIdle { assertEquals(translationLoads,state.opusLoadCount);assertEquals("i8mm",state.recognitionRuntime) }
    }
    @Test fun missingSelectedRecognizerNeverShowsMicrophone() {
        setup("missing-recognizer")
        ui.onNodeWithTag("voice.prepare").performClick()
        ui.waitUntil(90_000) { !state.busy }
        ui.runOnIdle { assertNotNull(state.error);assertFalse(state.voiceReady);assertFalse(state.recognitionReady);assertNull(state.recognitionRuntime) }
        ui.onNodeWithTag("voice.record").assertDoesNotExist()
    }
    @Test fun memorySavingKeepsOnlyPreparedRecognitionUntilTabExit() {
        setup()
        ui.runOnIdle { state.changeMemorySaving(true) }
        ui.onNodeWithTag("voice.prepare").performClick()
        ui.waitUntil(90_000) { !state.busy }
        ui.runOnIdle { assertNull(state.error);assertTrue(state.voiceReady);assertFalse(state.modelReady);assertEquals("i8mm",state.recognitionRuntime);state.mode="text" }
        ui.waitUntil(20_000) { state.recognitionRuntime==null }
        ui.runOnIdle { assertFalse(state.recognitionReady) }
    }
    @Test fun deferredVoiceReturnCannotReloadAfterCancellationPressureOrBackground() {
        setup()
        ui.runOnIdle { state.prepare() }
        ui.waitUntil(90_000) { !state.busy && state.voiceReady }
        for(stop in listOf<()->Unit>({ state.cancel() },{ state.trimMemory() },{ state.background() })) {
            ui.runOnIdle { state.trimMemory() }
            ui.waitUntil(20_000) { state.recognitionRuntime==null }
            ui.runOnIdle {
                state.prepare();state.mode="text";state.mode="voice"
                assertTrue(state.busy)
                stop()
            }
            ui.waitUntil(90_000) { !state.busy }
            // Drain work and its main-thread completions before checking no deferred reload.
            ui.waitForIdle()
            ui.runOnIdle { assertFalse(state.recognitionReady);assertNull(state.recognitionRuntime);state.foreground() }
        }
    }

}
