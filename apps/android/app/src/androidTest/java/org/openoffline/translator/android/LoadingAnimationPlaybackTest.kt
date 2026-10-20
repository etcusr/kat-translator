package org.openoffline.translator.android
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.lifecycle.ViewModelProvider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
@RunWith(AndroidJUnit4::class)
class LoadingAnimationPlaybackTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun processingShowsStatusAndCancelWithoutClips() {
        val state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
        ui.runOnUiThread { ui.activity.setContent { MaterialTheme(colorScheme=darkColorScheme()) { Processing(state,checkingPackages=false) } } }
        ui.onNodeWithTag("processing.animation").assertDoesNotExist()
        ui.onNodeWithTag("processing.status").assertExists()
        ui.onNodeWithTag("processing.cancel").assertHasClickAction()
        assertFalse(ui.activity.assets.list("")!!.any { it.endsWith(".mp4") || it=="loading-animations.json" })
    }
}
