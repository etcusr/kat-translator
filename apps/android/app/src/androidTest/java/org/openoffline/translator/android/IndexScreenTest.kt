package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.io.File

@RunWith(AndroidJUnit4::class)
class IndexScreenTest {
    val ui = createAndroidComposeRule<MainActivity>()
    @get:Rule val environment = UiTestEnvironment.wrap(ui)
    private fun screenshot(name: String) {
        ui.waitForIdle()
        val inst=InstrumentationRegistry.getInstrumentation()
        val bitmap=inst.uiAutomation.takeScreenshot()
        File(inst.targetContext.getExternalFilesDir(null),"ui-$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
        bitmap.recycle()
    }

    @Test fun iosNavigationAndTextEditing() {
        ui.onNodeWithText("Kat translator").assertIsDisplayed()
        ui.onNodeWithTag("mode.voice").assertIsSelected()
        screenshot("voice")
        ui.onNodeWithTag("mode.text").performClick()
        ui.onNodeWithTag("text.source.input").performTextInput("Привет 👋")
        ui.onNodeWithTag("text.source.count").assertTextContains("8", substring=true)
        ui.onNodeWithTag("text.source.expand").performClick()
        ui.onNodeWithTag("reader.text").assertTextEquals("Привет 👋")
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("text.clear.source").performClick()
        ui.onNodeWithTag("text.source.input").assertTextEquals("")
        ui.onNodeWithTag("language.target").performClick()
        ui.onNodeWithTag("language.search").performTextInput("Русский")
        ui.onNodeWithTag("language.row.ru").performClick()
        ui.onNodeWithTag("language.target").assertTextContains("Русский", substring=true)
        ui.onNodeWithTag("toolbar.history").performClick()
        ui.onNodeWithText("История переводов").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.onNodeWithText("Настройки", useUnmergedTree=true).assertIsDisplayed()
        screenshot("settings")
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("toolbar.models").performClick()
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag("model.index"))
        ui.onNodeWithTag("model.index").assertExists()
        screenshot("models")
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("mode.camera").performClick()
        ui.onNodeWithTag("camera.close").performClick()
        ui.onNodeWithTag("mode.text").assertIsSelected()
    }

    @Test fun translateFromIosTextWorkspaceAndRetainOnRotation() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val before=org.json.JSONArray(context.getSharedPreferences("kat",0).getString("history","[]"))
        val previousIds=(0 until before.length()).map { before.getJSONObject(it).getString("id") }.toSet()
        ui.onNodeWithTag("mode.text").performClick()
        ui.onNodeWithTag("language.target").performClick()
        ui.onNodeWithTag("language.row.en").performClick()
        ui.onNodeWithTag("text.source.input").performTextReplacement("Привет! Встреча завтра в 15:30.")
        ui.activityRule.scenario.recreate()
        ui.onNodeWithTag("text.source.input").assertTextEquals("Привет! Встреча завтра в 15:30.")
        ui.onNodeWithTag("text.translate").performClick()
        ui.waitUntil(180_000) { ui.onAllNodesWithTag("processing.overlay").fetchSemanticsNodes().isEmpty() }
        val output = ui.onNodeWithTag("text.translation.text").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString { it.text }
        assertTrue(output,(output.contains("15:30") || Regex("3:30\\s*PM",RegexOption.IGNORE_CASE).containsMatchIn(output)) && output.contains("tomorrow",ignoreCase=true))
        screenshot("text-result")
        ui.onNodeWithTag("toolbar.history").performClick()
        ui.onAllNodesWithText(output, substring=false).onFirst().assertIsDisplayed()
        val saved=org.json.JSONArray(context.getSharedPreferences("kat",0).getString("history","[]")).getJSONObject(0)
        assertEquals(output,saved.getString("translated"))
        assertFalse(previousIds.contains(saved.getString("id")))
        screenshot("history")
        ui.onNodeWithTag("sheet.close").performClick()
        File(context.getExternalFilesDir(null),"ui-acceptance.json").writeText(JSONObject().put("passed",true).put("interface","ios-parity").put("output",output).toString(2))
    }
}
