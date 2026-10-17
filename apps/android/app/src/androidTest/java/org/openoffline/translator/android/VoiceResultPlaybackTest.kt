package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Real OPUS -> Piper playback; does not record or save test history. */
class VoiceResultPlaybackTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    private fun state():TranslatorState {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.changeInterfaceLanguage("en")
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
        }
        ui.waitUntil(30_000) { state.packages.restored.value && !state.busy }
        return state
    }

    @Test fun bothVoicePanelsAreVisibleBeforeAndAfterResults() {
        val state=state()
        ui.runOnIdle { state.clear() }
        ui.onNodeWithTag("voice.original.text").performScrollTo().assertIsDisplayed()
        ui.onNodeWithTag("text.translation.text").performScrollTo().assertIsDisplayed()
        ui.runOnIdle { state.input="Исходный текст";state.output="Translated text" }
        ui.onNodeWithTag("voice.original.text").performScrollTo().assertTextEquals("Исходный текст")
        ui.onNodeWithTag("text.translation.text").performScrollTo().assertTextEquals("Translated text")
        ui.onNodeWithTag("voice.original.disclosure").assertDoesNotExist()
    }

    @Test fun automaticSpeechCanBeStoppedReplayedAndFinishNaturally() {
        val state=state()
        try {
            ui.runOnIdle {
                state.selectTranslation("opus")
                state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
                state.selectVoice("en","vits-piper-en_US-ljspeech-high")
                state.changeAutomaticSpeech(true);state.setPlaybackSpeed(1f)
                state.input="Здравствуйте. Я хотел бы забронировать номер в вашем отеле на завтра."
                state.translate()
            }
            ui.waitUntil(90_000) { state.playing || (!state.busy && state.error!=null) }
            ui.runOnIdle { assertNull(state.error);assertTrue(state.hasTranslatedAudio) }
            ui.onNodeWithTag("text.target.playback").performScrollTo()
                .assertIsEnabled().assertContentDescriptionEquals("Stop").performClick()
            ui.runOnIdle { assertFalse(state.playing);assertTrue(state.output.isNotBlank()) }
            ui.waitUntil(5_000) { !state.busy }
            ui.onNodeWithTag("text.target.playback").assertContentDescriptionEquals("Read translation aloud").performClick()
            ui.waitUntil(2_000) { state.playing }
            ui.onNodeWithTag("text.target.playback").assertContentDescriptionEquals("Stop")
            ui.onNodeWithTag("text.source.playback").assertContentDescriptionEquals("Play recording")
            ui.runOnIdle { state.pausePlayback() }
            ui.onNodeWithTag("text.target.playback").assertContentDescriptionEquals("Stop").performClick()
            ui.runOnIdle { assertFalse(state.playing);assertFalse(state.playbackPaused) }
            ui.onNodeWithTag("text.target.playback").assertContentDescriptionEquals("Read translation aloud").performClick()
            ui.waitUntil(2_000) { state.playing }
            ui.waitUntil(30_000) { !state.playing }
            ui.onNodeWithTag("text.target.playback").assertContentDescriptionEquals("Read translation aloud")
        } finally { ui.runOnIdle { state.stopPlayback();if(state.busy)state.cancel() } }
    }
}
