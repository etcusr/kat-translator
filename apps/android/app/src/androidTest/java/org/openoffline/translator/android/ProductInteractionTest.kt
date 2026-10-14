package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** User-visible controls, independent workspace state and persisted settings.
 * No inference, network, package deletion or history clearing is performed. */
@RunWith(AndroidJUnit4::class)
class ProductInteractionTest {
    val ui = createAndroidComposeRule<MainActivity>()
    @get:Rule val environment = UiTestEnvironment.wrap(ui)
    private fun state(): TranslatorState = ViewModelProvider(ui.activity)[TranslatorState::class.java]
    private fun waitFor(tag: String) {
        ui.waitUntil(5_000) { ui.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun textReaderClearAndWorkspaceIsolationSurviveRecreation() {
        ui.onNodeWithTag("mode.text").performClick()
        ui.onNodeWithTag("text.source.input").performTextReplacement("Original 👋 — 15:30")
        ui.onNodeWithTag("text.source.expand").performScrollTo().performClick()
        waitFor("reader.text")
        ui.onNodeWithTag("reader.text").assertTextEquals("Original 👋 — 15:30")
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("mode.voice").performClick()
        ui.runOnIdle { assertEquals("Voice must not inherit the text draft", "", state().input) }
        ui.onNodeWithTag("mode.text").performClick()
        ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("text.source.input").performScrollTo().assertTextEquals("Original 👋 — 15:30")
        ui.onNodeWithTag("text.clear.source").performScrollTo().performClick()
        ui.onNodeWithTag("text.source.input").assertTextEquals("")
        ui.onNodeWithTag("text.source.expand").assertIsNotEnabled()
        ui.onNodeWithTag("text.copy.source").assertIsNotEnabled()
        ui.onNodeWithTag("text.share.source").assertIsNotEnabled()
    }

    @Test fun languageSearchSelectionAndFavoriteAreRestoredWhenReopened() {
        var source = ""; var target = ""; var favorite = false
        ui.runOnIdle { source=state().source;target=state().target;favorite="ja" in state().favorites;state().selectTranslation("index") }
        try {
            ui.onNodeWithTag("mode.text").performClick()
            ui.onNodeWithTag("language.target").performScrollTo().performClick()
            waitFor("language.search")
            ui.onNodeWithTag("language.search").performTextInput("ja")
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.row.ja"))
            ui.onNodeWithTag("language.row.ja").assertExists()
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.favorite.ja"))
            ui.onNodeWithTag("language.favorite.ja").assertIsDisplayed().performClick()
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.row.ja"))
            ui.onNodeWithTag("language.row.ja").performClick()
            ui.runOnIdle {
                assertEquals("ja",state().target)
                assertEquals(!favorite,"ja" in state().favorites)
            }
            ui.activityRule.scenario.recreate()
            ui.onNodeWithTag("language.target").performScrollTo().performClick()
            waitFor("language.search")
            ui.onNodeWithTag("language.search").performTextInput("ja")
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.row.ja"))
            ui.onNodeWithTag("language.row.ja").assertExists()
            ui.runOnIdle { assertEquals(!favorite,"ja" in state().favorites) }
            ui.onNodeWithTag("sheet.close").performClick()
        } finally {
            ui.runOnIdle {
                if(("ja" in state().favorites)!=favorite)state().toggleFavorite("ja")
                state().chooseLanguage(source,true);state().chooseLanguage(target,false)
            }
        }
    }

    @Test fun historySwitchPersistsAndCancellingClearKeepsHistory() {
        var enabled = true; var ids = emptyList<String>()
        ui.runOnIdle { enabled=state().recordHistory;ids=state().history.map { it.id } }
        try {
            ui.onNodeWithTag("toolbar.settings").performClick()
            waitFor("settings.recordText")
            ui.onNodeWithTag("settings.recordText").performScrollTo().performClick()
            ui.runOnIdle { assertEquals(!enabled,state().recordHistory) }
            ui.onNodeWithTag("sheet.close").performClick()
            ui.activityRule.scenario.recreate()
            ui.onNodeWithTag("toolbar.settings").performClick()
            waitFor("settings.recordText")
            ui.onNodeWithTag("settings.recordText").performScrollTo().let {
                if(enabled)it.assertIsOff() else it.assertIsOn()
            }
            ui.onNodeWithTag("settings.clearHistory").performScrollTo().performClick()
            // Back dismisses the destructive confirmation without clearing any records.
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation
                .performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            ui.waitForIdle()
            ui.runOnIdle { assertEquals(ids,state().history.map { it.id }) }
        } finally { ui.runOnIdle { state().setHistory(enabled) } }
    }
}
