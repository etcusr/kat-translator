package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog

@RunWith(AndroidJUnit4::class)
class MenuNavigationTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun nestedDoneReturnsToThePresentingScreenAndPreservesSelectedModel() {
        var model=""
        ui.runOnIdle { model=ViewModelProvider(ui.activity)[TranslatorState::class.java].translationModel }
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.onNodeWithTag("settings.recognition.models").performScrollTo().performClick()
        ui.onNodeWithTag("models.list").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("settings.recognition.models").performScrollTo().assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()

        ui.onNodeWithTag("toolbar.models").performClick()
        val info="model.info.${PackageCatalog.INDEX_ID}"
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag(info))
        ui.onNodeWithTag(info).performClick()
        ui.onNodeWithTag("model.languages.open").performScrollTo().performClick()
        ui.onNodeWithTag("model.languages.count").assertTextContains("150",substring=true)
        ui.onNodeWithTag("model.languages.search").performTextInput("Japanese")
        ui.onNodeWithTag("model.languages.row.ja").assertExists()
        ui.onNodeWithTag("sheet.back").performClick()
        ui.onNodeWithTag("model.languages.open").assertExists()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("models.list").assertIsDisplayed()
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag("models.languageSetup"))
        ui.onNodeWithTag("models.languageSetup").performClick()
        ui.onNodeWithTag("setup.search.primary").assertExists()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("models.list").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("sheet.container").assertDoesNotExist()
        ui.runOnIdle { assertEquals(model,ViewModelProvider(ui.activity)[TranslatorState::class.java].translationModel) }
    }
}
