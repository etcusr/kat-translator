package org.openoffline.translator.android
import androidx.activity.compose.setContent
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
@RunWith(AndroidJUnit4::class)
class StartupPreparationTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(RuleChain.outerRule(object:ExternalResource() {
        override fun before() { check(InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("kat",0).edit()
            .putBoolean("automaticModelLoad",true).putBoolean("memorySaving",false).putString("translationModel","opus")
            .putString("source","ru").putString("target","en").remove("unfinishedAutomaticModelLoad").commit()) }
    }).around(ui))
    @Test fun startupWaitsForRepositoryThenLoadsWeightsAndPreparationShowsProgressAndHint() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
        ui.waitUntil(30_000) { state.packages.restored.value && !state.busy && state.modelReady }
        ui.runOnIdle { assertNull(state.error);assertEquals(1,state.opusLoadCount);assertEquals(1,state.opusWeightLoadCount) }
        ui.onNodeWithTag("voice.prepare").assertDoesNotExist()
        ui.runOnUiThread { ui.activity.setContent { Processing(state,checkingPackages=true) } }
        ui.onNodeWithTag("models.preparation").assertIsDisplayed()
        ui.onNodeWithTag("models.firstVerificationHint").assertIsDisplayed()
        ui.onNodeWithTag("processing.cancel").assertDoesNotExist()
        ui.onNodeWithTag("processing.animation").assertDoesNotExist()
        val bitmap=InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
        try { java.io.File(ui.activity.getExternalFilesDir(null),"parity-preparation.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } } finally { bitmap.recycle() }
    }
}
