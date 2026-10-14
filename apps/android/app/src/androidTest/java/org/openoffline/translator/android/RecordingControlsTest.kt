package org.openoffline.translator.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Actual microphone lifecycle; transient PCM is discarded, never saved or recognized. */
@RunWith(AndroidJUnit4::class)
class RecordingControlsTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun pauseResumeCancelAndBackgroundReleaseTheMicrophone() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            assertEquals("Grant microphone permission before this test",PackageManager.PERMISSION_GRANTED,
                ui.activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.changeInterfaceLanguage("en")
            state.changeRecordingMode("toggle");state.changeRecordingPreprocessing(false)
            state.setSilence(30);state.setHistory(false);state.changeRecordAudio(false)
        }
        try {
            ui.onNodeWithTag("voice.record").performScrollTo().performClick()
            ui.waitUntil(10_000) { state.recordingMillis>=500 || state.error!=null }
            ui.runOnIdle { assertNull(state.error);assertTrue(state.recording) }
            ui.onNodeWithText("Pause",useUnmergedTree=true).performScrollTo().performClick()
            ui.waitUntil { state.recordingPaused }
            // Let the UI ticker observe the final buffer written before pause.
            SystemClock.sleep(250)
            var paused=0L
            ui.runOnIdle { paused=state.recordingMillis }
            SystemClock.sleep(600)
            ui.runOnIdle { assertEquals("Paused time must not enter captured PCM",paused,state.recordingMillis) }
            ui.onNodeWithText("Resume",useUnmergedTree=true).performClick()
            ui.waitUntil(5_000) { state.recordingMillis>=paused+300 }
            ui.onNodeWithText("Cancel",useUnmergedTree=true).performClick()
            ui.waitUntil { !state.recording }
            ui.runOnIdle { assertFalse(state.busy);assertFalse(state.hasOriginalAudio);assertEquals("",state.input) }
            ui.onNodeWithTag("voice.record").performScrollTo().performClick()
            ui.waitUntil(5_000) { state.recordingMillis>=300 }
            ui.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
            ui.waitUntil(5_000) { !state.recording }
            ui.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            ui.runOnIdle { assertFalse(state.busy);assertFalse(state.hasOriginalAudio);assertNull(state.error) }
        } finally {
            ui.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            ui.runOnIdle { if(state.recording)state.discardRecording() }
        }
    }
}
