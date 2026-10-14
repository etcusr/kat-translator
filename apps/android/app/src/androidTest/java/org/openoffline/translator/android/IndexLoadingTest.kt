package org.openoffline.translator.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class IndexLoadingTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun profileTwoPreparationsAndVerifyReuse() {
        lateinit var state:TranslatorState
        ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java];state.changeMemorySaving(false);state.selectTranslation("index") }
        ui.waitUntil(60_000) { state.packages.restored.value }
        val results=JSONArray()
        repeat(2) { attempt ->
            val start=System.nanoTime()
            ui.runOnIdle { state.prepare() }
            ui.waitUntil(180_000) { !state.busy }
            val seconds=(System.nanoTime()-start)/1e9
            ui.runOnIdle { assertNull(state.error);assertTrue(state.modelReady);state.prepare();assertFalse(state.busy) }
            results.put(JSONObject().put("attempt",attempt+1).put("preparationSeconds",seconds).put("mtp",state.mtp))
            ui.runOnIdle { state.unload() }
            ui.waitUntil(20_000) { !state.modelReady }
        }
        File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir,"index-load-profile.json").writeText(results.toString(2))
    }
}
