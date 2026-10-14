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
@RunWith(AndroidJUnit4::class)
class ToggleRecordingDefaultTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(RuleChain.outerRule(object:ExternalResource() {
        override fun before() { check(InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("kat",0).edit().remove("recordingMode").commit()) }
    }).around(ui))
    @Test fun defaultTapContinuesRecordingAfterReleaseUntilSecondTap() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java];assertEquals("toggle",state.recordingMode)
            state.setSilence(30);state.setHistory(false);state.changeRecordAudio(false);state.changeRecordingPreprocessing(false)
        }
        ui.waitUntil(30_000) { state.packages.restored.value }
        try {
            ui.onNodeWithTag("voice.record").performScrollTo().performTouchInput { click() }
            ui.waitUntil(5_000) { state.recordingMillis>=600 || state.error!=null }
            ui.runOnIdle { assertNull(state.error);assertTrue(state.recording);assertFalse(state.busy) }
            // Second actual tap submits; cancel immediately so a private microphone sample is never retained.
            ui.onNodeWithTag("voice.record").performTouchInput { click() }
            ui.runOnUiThread { assertFalse(state.recording);state.cancel() }
            ui.waitUntil(15_000) { !state.busy }
        } finally { ui.runOnIdle { if(state.recording)state.discardRecording();state.clear() } }
    }
}
