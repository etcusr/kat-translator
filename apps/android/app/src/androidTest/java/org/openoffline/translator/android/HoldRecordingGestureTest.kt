package org.openoffline.translator.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android touch dispatch and AudioRecord; no fake recognition or retained microphone PCM. */
@RunWith(AndroidJUnit4::class)
class HoldRecordingGestureTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private lateinit var state:TranslatorState
    private var downTime=0L
    private var x=0f
    private var y=0f

    private fun prepare(silence:Int=30) {
        ui.runOnIdle {
            assertEquals(PackageManager.PERMISSION_GRANTED,ui.activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.changeRecordingMode("hold");state.changeRecordingPreprocessing(false)
            state.setSilence(silence);state.setHistory(false);state.changeRecordAudio(false);state.changeRecordImages(false)
        }
        ui.waitUntil(30_000) { state.packages.restored.value }
        ui.waitForIdle()
        ui.onNodeWithTag("voice.record").performScrollTo()
        val bounds=ui.onNodeWithTag("voice.record").fetchSemanticsNode().boundsInWindow
        x=bounds.center.x;y=bounds.center.y;downTime=SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN)
        ui.waitUntil(5_000) { state.recordingMillis>=400 || state.error!=null }
        ui.runOnUiThread { assertNull(state.error);assertTrue(state.recording);assertFalse(state.busy) }
    }

    private fun touch(action:Int,dy:Float=0f,after:()->Unit={}) {
        // Dispatch through Activity/AndroidComposeView in actual window coordinates. Up
        // and immediate cancellation share one main-thread turn, avoiding lengthy ASR.
        ui.runOnUiThread {
            val event=MotionEvent.obtain(downTime,SystemClock.uptimeMillis(),action,x,y+dy,0)
            event.source=InputDevice.SOURCE_TOUCHSCREEN
            try { ui.activity.dispatchTouchEvent(event);after() } finally { event.recycle() }
        }
    }

    @Test fun movementBeyondTouchSlopKeepsRecordingUntilPhysicalUp() {
        try {
            prepare()
            val distance=ui.activity.resources.displayMetrics.density*150f
            for(step in 1..12) {
                touch(MotionEvent.ACTION_MOVE,-distance*step/12)
                SystemClock.sleep(30)
                ui.runOnUiThread {
                    assertTrue("A held finger must survive movement, including outside the microphone",state.recording)
                    assertFalse("Movement must not submit microphone PCM",state.busy)
                }
            }
            SystemClock.sleep(400)
            ui.runOnUiThread { assertTrue(state.recording);assertFalse(state.busy) }
            touch(MotionEvent.ACTION_UP,-distance) {
                assertFalse("Only physical release should stop the hold",state.recording)
                assertTrue("Release must submit the captured recording",state.busy)
                state.cancel()
            }
            ui.waitUntil(15_000) { !state.busy }
        } finally { cleanup() }
    }

    @Test fun cancelledTouchDiscardsWithoutSubmitting() {
        try {
            prepare()
            touch(MotionEvent.ACTION_CANCEL)
            ui.waitUntil(5_000) { !state.recording }
            ui.runOnUiThread { assertFalse(state.busy);assertFalse(state.hasOriginalAudio);assertEquals("",state.input) }
        } finally { cleanup() }
    }

    @Test fun holdingPastConfiguredSilenceDoesNotSubmit() {
        try {
            prepare(silence=1)
            ui.waitUntil(5_000) { state.recordingMillis>=2_000 || !state.recording }
            ui.runOnUiThread { assertTrue("Silence must not submit while the finger is held",state.recording);assertFalse(state.busy) }
            touch(MotionEvent.ACTION_CANCEL)
            ui.runOnUiThread { assertFalse(state.recording);assertFalse(state.busy) }
        } finally { cleanup() }
    }

    @Test fun leavingVoiceWorkspaceDuringHoldDiscardsWithoutSubmitting() {
        try {
            prepare()
            ui.runOnUiThread { state.mode="text" }
            ui.waitUntil(5_000) { !state.recording }
            ui.runOnUiThread { assertFalse(state.busy);assertFalse(state.hasOriginalAudio) }
            touch(MotionEvent.ACTION_CANCEL)
        } finally { cleanup() }
    }

    private fun cleanup() {
        if(!::state.isInitialized)return
        touch(MotionEvent.ACTION_CANCEL)
        ui.runOnUiThread { if(state.recording)state.discardRecording();if(state.busy)state.cancel() }
        ui.waitUntil(15_000) { !state.busy }
        ui.runOnUiThread { state.clear() }
    }
}
