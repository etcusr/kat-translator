package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The actual Cancel control must leave the fixed Index model usable for the next request. */
@RunWith(AndroidJUnit4::class)
class ProcessingCancellationTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun cancelThenTranslateAgainThroughTextButtons() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="text";state.setHistory(false);state.changeRecordAudio(false)
            state.changeAutomaticSpeech(false);state.selectTranslation("index")
            state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
        }
        ui.onNodeWithTag("text.source.input").performTextReplacement("Завтра состоится встреча. Обсудим расписание поездов, билеты и время прибытия. ".repeat(20))
        ui.onNodeWithTag("text.translate").performClick()
        ui.waitUntil(120_000) { state.ready && state.busy && state.segmentCount>0 || !state.busy }
        ui.runOnIdle { assertTrue("The long request must still be active",state.busy) }
        ui.onNodeWithTag("processing.cancel").performScrollTo().performClick()
        ui.waitUntil(45_000) { !state.busy }
        ui.onNodeWithTag("processing.overlay").assertDoesNotExist()
        ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement("Привет! Встреча завтра в 15:30.")
        ui.onNodeWithTag("text.translate").performClick()
        ui.waitUntil(180_000) { !state.busy }
        ui.runOnIdle {
            assertNull(state.error)
            assertTrue(state.output,state.output.contains("tomorrow",true))
            assertTrue(state.output,state.output.contains("15:30") || Regex("3:30\\s*PM",RegexOption.IGNORE_CASE).containsMatchIn(state.output))
        }
        ui.onNodeWithTag("text.translation.text").performScrollTo().assertIsDisplayed()
    }
}
