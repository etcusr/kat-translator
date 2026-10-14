package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ModelLifecycleTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private lateinit var state:TranslatorState
    private fun setup() {
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.selectTranslation("opus");state.changeMemorySaving(false);state.mode="voice"
            state.setHistory(false);state.changeRecordAudio(false);state.changeRecordImages(false)
            state.chooseLanguage("en",false);state.chooseLanguage("ru",true);state.changeAutomaticSpeech(false)
        }
        ui.waitUntil(30_000) { state.packages.restored.value }
    }
    private fun translate(text:String) {
        ui.runOnIdle { state.mode="text";state.changeAutomaticSpeech(false);state.input=text;state.translate() }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertNull(state.error);assertTrue(state.output.isNotBlank()) }
    }
    @Test fun manualPrepareKeepsWeightsAcrossTranslationsSpeechAndExplicitlyUnloads() {
        setup()
        ui.onNodeWithTag("voice.prepare").performClick()
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertNull(state.error);assertTrue(state.modelReady);assertFalse(state.ready);assertEquals(1,state.opusLoadCount);assertEquals(1,state.opusWeightLoadCount) }
        ui.onNodeWithTag("voice.prepare").assertDoesNotExist()
        translate("Поезд отправляется завтра в 10:30.")
        ui.runOnIdle { assertEquals(1,state.opusWeightLoadCount);state.readText(false) }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertNull(state.error);assertTrue(state.modelReady);state.stopPlayback() }
        translate("Спасибо за помощь.")
        ui.runOnIdle {
            assertEquals("Both context and weights must remain loaded",1,state.opusLoadCount)
            assertEquals(1,state.opusWeightLoadCount);state.unload()
        }
        ui.waitUntil(5_000) { !state.modelReady }
        translate("Доброе утро.")
        ui.runOnIdle { assertEquals(2,state.opusLoadCount);assertEquals(2,state.opusWeightLoadCount);state.changeMemorySaving(true) }
        ui.waitUntil(5_000) { !state.modelReady }
        translate("До свидания.")
        ui.runOnIdle { assertFalse("Memory saving must still release weights",state.modelReady);assertEquals(3,state.opusLoadCount) }
    }
    @Test fun automaticPreparationOnlyRunsOnceAfterRestoreAndCanBeDisabled() {
        setup()
        ui.runOnIdle { assertFalse(state.modelReady);state.tryAutomaticPrepare();assertFalse(state.busy);state.changeAutomaticLoad(true) }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertTrue(state.modelReady);assertNull(state.error);state.tryAutomaticPrepare();assertFalse(state.busy);assertEquals(1,state.opusWeightLoadCount) }
    }
}
