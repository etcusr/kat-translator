package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import android.content.pm.ActivityInfo
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** UI-only regressions for the user's models-list oscillation video and focused-input navigation.
 * These do not run model inference, download models or change installed packages. */
@RunWith(AndroidJUnit4::class)
class WorkspaceNavigationTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun modelsSwipeKeepsWindowAndHeaderStable() {
        ui.onNodeWithTag("toolbar.models").performClick()
        ui.waitForIdle()
        val header=ui.onNodeWithTag("sheet.header").fetchSemanticsNode().boundsInRoot
        val window=ui.onNodeWithTag("sheet.container").fetchSemanticsNode().boundsInRoot
        val automation=InstrumentationRegistry.getInstrumentation().uiAutomation
        fun screenshot(name:String) {
            automation.takeScreenshot()?.let { bitmap ->
                try { java.io.File(ui.activity.getExternalFilesDir(null),name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } }
                finally { bitmap.recycle() }
            }
        }
        screenshot("ui-models-top.png")
        val headerNode=ui.onNodeWithTag("sheet.header").fetchSemanticsNode()
        fun screenHeader():Rect {
            val origin=IntArray(2)
            ui.activity.window.decorView.getLocationOnScreen(origin)
            val bounds=headerNode.boundsInWindow
            return Rect(bounds.left.toInt()+origin[0],bounds.top.toInt()+origin[1],bounds.right.toInt()+origin[0],bounds.bottom.toInt()+origin[1])
        }
        lateinit var initialScreen:Rect
        val samples=CopyOnWriteArrayList<Rect>()
        val movingSamples=CopyOnWriteArrayList<Rect>()
        val sampling=AtomicBoolean(true)
        val moving=AtomicBoolean(false)
        // Read current layout coordinates and the actual window origin on every display
        // frame. Accessibility caches may point at the previously closed dialog.
        val sampler=object:android.view.Choreographer.FrameCallback {
            override fun doFrame(time:Long) {
                if(!sampling.get())return
                val bounds=screenHeader();samples.add(bounds)
                if(moving.get())movingSamples.add(bounds)
                android.view.Choreographer.getInstance().postFrameCallback(this)
            }
        }
        ui.runOnUiThread { initialScreen=screenHeader();android.view.Choreographer.getInstance().postFrameCallback(sampler) }
        val list=ui.onNodeWithTag("models.list").fetchSemanticsNode().boundsInWindow
        fun listPosition()=ui.onNodeWithTag("models.list").fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].value()
        val initialPosition=listPosition()
        val x=list.center.x
        fun swipe(up:Boolean) {
            val start=if(up)list.bottom-40 else list.top+40
            val end=if(up)list.top+40 else list.bottom-40
            val down=SystemClock.uptimeMillis()
            fun inject(action:Int,y:Float) {
                val event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0).apply { source=android.view.InputDevice.SOURCE_TOUCHSCREEN }
                try { assertTrue(automation.injectInputEvent(event,true)) } finally { event.recycle() }
            }
            moving.set(true)
            try {
                inject(MotionEvent.ACTION_DOWN,start)
                for(frame in 1..30) {
                    SystemClock.sleep(16)
                    inject(MotionEvent.ACTION_MOVE,start+(end-start)*frame/30f)
                }
                inject(MotionEvent.ACTION_UP,end)
                SystemClock.sleep(180)
            } finally { moving.set(false) }
        }
        try {
            repeat(8) { attempt ->
                swipe(up=attempt%2==0)
                ui.waitForIdle()
                if(attempt==0) { assertTrue("The real upward gesture must move list content",listPosition()>initialPosition);screenshot("ui-models-bottom.png") }
                assertEquals("Header must not follow or bounce with the list",header,ui.onNodeWithTag("sheet.header").fetchSemanticsNode().boundsInRoot)
                assertEquals("Models window height must stay fixed",window,ui.onNodeWithTag("sheet.container").fetchSemanticsNode().boundsInRoot)
            }
        } finally { sampling.set(false);ui.runOnUiThread { android.view.Choreographer.getInstance().removeFrameCallback(sampler) } }
        assertTrue("Need observations while real pointer gestures are active",movingSamples.size>=8)
        samples.forEach { bounds -> assertEquals("Header moved on screen during a gesture",initialScreen,bounds) }
        // Stationary frames after fling: no alternating layout/scroll feedback.
        val settled=ui.onNodeWithTag("models.list").fetchSemanticsNode().boundsInRoot
        repeat(5) { ui.mainClock.advanceTimeBy(200);ui.waitForIdle();assertEquals(settled,ui.onNodeWithTag("models.list").fetchSemanticsNode().boundsInRoot) }
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("toolbar.models").performClick()
        assertEquals("Reopening starts at the top",initialPosition,listPosition())
        assertEquals(header,ui.onNodeWithTag("sheet.header").fetchSemanticsNode().boundsInRoot)
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.onNodeWithTag("sheet.header").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
    }
    @Test fun focusedTextNavigationDismissesKeyboardAndResultRemainsReachable() {
        ui.onNodeWithTag("mode.text").performClick()
        ui.onNodeWithTag("text.source.input").performTextInput("A line to edit while the keyboard is open.")
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("sheet.header").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithTag("sheet.header").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("text.source.input").performClick()
        ui.onNodeWithTag("language.target").performClick()
        ui.waitUntil(5_000) { ui.onAllNodesWithTag("language.search").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithTag("language.search").assertIsDisplayed()
        ui.onNodeWithTag("sheet.close").performClick()
        ui.onNodeWithTag("text.source.input").performClick()
        ui.onNodeWithTag("mode.camera").performClick()
        ui.onNodeWithTag("camera.capture").assertIsDisplayed()
        ui.waitUntil(5_000) { ViewCompat.getRootWindowInsets(ui.activity.window.decorView)?.isVisible(WindowInsetsCompat.Type.ime())!=true }
        ui.onNodeWithTag("camera.close").performClick()
        ui.onNodeWithTag("text.translation.text").performScrollTo().assertIsDisplayed()
        ui.onNodeWithTag("text.source.input").performScrollTo().assertTextContains("A line to edit",substring=true)
    }
    @Test fun rapidCameraOpenCloseSurvivesLateSessionCallbacks() {
        repeat(12) {
            ui.onNodeWithTag("mode.camera").performClick()
            ui.onNodeWithTag("camera.capture").assertIsDisplayed()
            ui.onNodeWithTag("camera.close").performClick()
            ui.onNodeWithTag("mode.voice").assertIsDisplayed()
        }
        android.os.SystemClock.sleep(500)
        ui.onNodeWithTag("mode.text").performClick()
        ui.onNodeWithTag("text.source.input").assertIsDisplayed()
    }
    @Test fun landscapeVoiceControlsRemainReachable() {
        val original=ui.activity.requestedOrientation
        ui.runOnUiThread { ui.activity.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        try {
            ui.waitUntil(5_000) { ui.activity.resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE }
            ui.onNodeWithTag("mode.voice").performClick()
            ui.onNodeWithTag("voice.record").performScrollTo().assertIsDisplayed()
            ui.onNodeWithTag("voice.import").performScrollTo().assertIsDisplayed()
            ui.onNodeWithTag("language.target").performScrollTo().assertIsDisplayed()
        } finally { ui.runOnUiThread { ui.activity.requestedOrientation=original } }
    }

}
