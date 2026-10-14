package org.openoffline.translator.android
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
class CatAnimationRenderingTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun rendersMovingCatOnBlackWithClockControlledFrames() {
        ui.mainClock.autoAdvance=false
        ui.runOnUiThread { ui.activity.setContent {
            Box(Modifier.fillMaxSize().background(Color.Black),contentAlignment=Alignment.Center) {
                CatProgress(modifier=Modifier.testTag("cat"),prominent=true)
            }
        } }
        ui.mainClock.advanceTimeBy(32)
        ui.onNodeWithTag("cat").assertIsDisplayed()
        for(i in 0..7) {
            ui.mainClock.advanceTimeBy(2000)
            ui.waitForIdle()
            val bitmap=InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
            try { java.io.File(ui.activity.getExternalFilesDir(null),"cat-frame-$i.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) } }
            finally { bitmap.recycle() }
        }
    }
}
