package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/** Exercise the no-saved-selection default through actual product buttons. */
@RunWith(AndroidJUnit4::class)
class OpusDefaultFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(RuleChain.outerRule(object:ExternalResource() {
        override fun before() {
            check(InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("kat",0)
                .edit().remove("translationModel").commit())
        }
    }).around(ui))

    @Test fun freshDefaultTranslatesThroughOpusAndRetainsManualIndexChoice() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            assertEquals(AUTO_TRANSLATION,state.translationModel)
            state.mode="text";state.setHistory(false);state.changeRecordAudio(false)
            state.changeAutomaticSpeech(false);state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
        }
        ui.waitUntil(30_000) { state.packages.restored.value && state.deviceClass!=null }
        ui.onNodeWithTag("toolbar.models").performClick()
        ui.onNodeWithTag("models.list",useUnmergedTree=true).performScrollToNode(hasTestTag("model.select.auto"))
        ui.onNodeWithTag("model.select.auto",useUnmergedTree=true).assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        // Use the shared OPUS 10:30 acceptance fixture. A separate observed
        // 15:30 -> 3:30 without PM quality defect is retained in the device report;
        // this test checks default routing and persistence, not arbitrary translation quality.
        ui.onNodeWithTag("text.source.input").performTextReplacement("Поезд отправляется завтра в 10:30.")
        ui.onNodeWithTag("text.translate").assertIsDisplayed().performClick()
        ui.waitUntil(90_000) { !state.busy }
        ui.runOnIdle {
            assertNull(state.error);assertEquals(AUTO_TRANSLATION,state.translationModel)
            // Mid-range devices route RU->EN to the installed OPUS package.
            if(!state.strongDevice)assertEquals("opus",state.effectiveModel)
            assertTrue(state.output,state.output.contains("tomorrow",true))
            assertTrue(state.output,state.output.contains("10:30"))
            if(!state.strongDevice)assertFalse("OPUS must not allocate Index",state.ready)
            // An explicit choice survives recreation; defaults must not overwrite it.
            state.selectTranslation("index")
        }
        ui.activityRule.scenario.recreate()
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            assertEquals("index",state.translationModel)
        }
    }
}
