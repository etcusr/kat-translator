package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ParityDetailsTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private fun screenshot(name:String) {
        val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
        try { java.io.File(ui.activity.getExternalFilesDir(null),name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } } finally { bitmap.recycle() }
    }
    @Test fun languageLegendShowsEachActualSymbolAndVoiceOriginalStaysVisible() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
        ui.waitUntil(30_000) { state.packages.restored.value }
        ui.onNodeWithTag("language.target").performScrollTo().performClick()
        ui.onNodeWithTag("language.legend").performClick()
        listOf("recognition","ready","download","checking","unavailable").forEach {
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.legend.icon.$it"))
            ui.onNodeWithTag("language.legend.icon.$it",useUnmergedTree=true).assertIsDisplayed()
        }
        screenshot("parity-language-legend.png")
        ui.onNodeWithTag("sheet.close").performClick()
        ui.runOnIdle { state.mode="voice";state.input="Исходный текст";state.output="Translated text" }
        ui.onNodeWithTag("text.translation.text").performScrollTo().assertTextEquals("Translated text")
        ui.onNodeWithTag("voice.original.text").performScrollTo().assertTextEquals("Исходный текст")
        ui.onNodeWithTag("voice.original.disclosure").assertDoesNotExist()
        ui.onNodeWithTag("text.share.source").assertIsNotEnabled()
        screenshot("parity-voice-results.png")
    }
    @Test fun loadedOpusCanBeUnloadedFromModelsMenu() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java];state.selectTranslation("opus");state.chooseLanguage("ru",true);state.chooseLanguage("en",false) }
        ui.waitUntil(30_000) { state.packages.restored.value }
        ui.runOnIdle { state.prepare() }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertTrue(state.modelReady);assertFalse(state.ready) }
        ui.onNodeWithTag("toolbar.models").performClick()
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag("model.unload"))
        ui.onNodeWithTag("model.unload").assertIsEnabled().performClick()
        ui.waitUntil(5_000) { !state.modelReady }
        ui.onNodeWithTag("model.unload").assertIsNotEnabled()
    }
}
