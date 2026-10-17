package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Focused settings check; does not touch history, recording controls, brightness or lock state. */
class WhisperDateTimeSettingTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun defaultOffTogglePersistsAcrossActivityCloseAndRelaunch() {
        ui.runOnIdle {
            val state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            assertFalse(state.whisperDateTimeRepair)
            assertTrue(state.recordingPreprocessing)
        }
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.onNodeWithTag("settings.whisperDateTimeRepair").performScrollTo().performClick()
        ui.runOnIdle {
            assertTrue(ViewModelProvider(ui.activity)[TranslatorState::class.java].whisperDateTimeRepair)
            assertTrue(ui.activity.getSharedPreferences("kat",0).getBoolean("whisperDateTimeRepair",false))
        }
        ui.activityRule.scenario.close()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity {
                val state=ViewModelProvider(it)[TranslatorState::class.java]
                assertTrue(state.whisperDateTimeRepair)
                assertTrue(state.recordingPreprocessing)
                state.changeWhisperDateTimeRepair(false)
            }
        }
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity {
                val state=ViewModelProvider(it)[TranslatorState::class.java]
                assertFalse(state.whisperDateTimeRepair)
                assertTrue(state.recordingPreprocessing)
            }
        }
    }
}
