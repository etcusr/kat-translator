package org.openoffline.translator.android
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.lifecycle.ViewModelProvider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
@RunWith(AndroidJUnit4::class)
class LoadingAnimationPlaybackTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun realDecoderRotatesAtClipEndAndNextScreenDoesNotRepeat() {
        val state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
        fun display() { ui.runOnUiThread { ui.activity.setContent { MaterialTheme(colorScheme=darkColorScheme()) { Processing(state,checkingPackages=false) } } } }
        fun checkLayout() {
            val stage=ui.onNodeWithTag("processing.overlay").fetchSemanticsNode().boundsInRoot
            val video=ui.onNodeWithTag("processing.animation").fetchSemanticsNode().boundsInRoot
            assertEquals(stage.center.x,video.center.x,2f)
            assertTrue("Animation must not sit at the top edge",video.top>stage.height*.1f)
            val pixels=ui.onNodeWithTag("processing.overlay").captureToImage().toPixelMap()
            assertEquals(Color.Black,pixels[2,pixels.height/2])
        }
        display()
        fun current()=ui.onNodeWithTag("processing.animation").fetchSemanticsNode().config[SemanticsProperties.StateDescription]
        ui.waitUntil(5_000) { current().isNotBlank() }
        checkLayout();val first=current()
        ui.waitUntil(30_000) { current()!=first }
        checkLayout();val second=current();assertNotEquals(first,second)
        ui.runOnUiThread { ui.activity.setContent { Box(Modifier.fillMaxSize().background(Color.Black)) } };ui.waitForIdle()
        display()
        ui.waitUntil(5_000) { current().isNotBlank() }
        assertNotEquals(second,current())
    }
}
