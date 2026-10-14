package org.openoffline.translator.android

import android.graphics.Bitmap
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Layout audit of the panel screens: inside every Group card, the first element of each line
 * starts at the card's text edge. A small offset (a TextButton's 12 dp inner padding, a stray
 * indent) is the "not quite even" look; an offset of 24 dp or more is a leading icon (icons have
 * no semantics) and is allowed. Read-only: nothing is downloaded or selected. */
@RunWith(AndroidJUnit4::class)
class UiLayoutAuditTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private val density get()=ui.activity.resources.displayMetrics.density

    private fun texts(node:SemanticsNode):List<SemanticsNode> =
        node.children.flatMap { child -> (if(child.config.getOrNull(SemanticsProperties.Text)!=null) listOf(child) else emptyList())+texts(child) }

    private fun label(node:SemanticsNode)=node.config.getOrNull(SemanticsProperties.Text)?.joinToString().orEmpty().take(60)

    /** Misaligned line starts in the Group cards currently on screen. */
    private fun audit(screen:String):List<String> {
        val screenHeight=ui.activity.resources.displayMetrics.heightPixels
        val problems=mutableListOf<String>()
        // Prefetched LazyColumn items are composed but not placed; they report the root origin.
        for(group in ui.onAllNodesWithTag("ui.group",useUnmergedTree=true).fetchSemanticsNodes().filter { it.layoutInfo.isPlaced && it.boundsInRoot.left>=1f }) {
            val edge=group.boundsInRoot.left+16*density
            val visible=texts(group).filter { val b=it.boundsInRoot;b.height>0 && b.top>=0 && b.bottom<=screenHeight }
            for(text in visible) {
                // The audit runs in Russian: sizes must use Russian units, not «MB/GB».
                if(Regex("\\d[.,\\d]*[\\s\u00A0](MB|GB|KB)\\b").containsMatchIn(text.config.getOrNull(SemanticsProperties.Text)?.joinToString().orEmpty()))problems+="$screen: «${label(text)}» uses English size units"
                val b=text.boundsInRoot
                val leftmost=visible.none { other -> other!==text && overlap(b,other.boundsInRoot) && other.boundsInRoot.left<b.left-density }
                if(!leftmost)continue
                val offset=(b.left-edge)/density
                if(offset in 2f..24f || offset< -2f)problems+="$screen: «${label(text)}» starts ${"%.0f".format(offset)} dp from the card edge (card ${group.boundsInRoot}, text $b)"
            }
        }
        return problems
    }

    private fun overlap(a:Rect,b:Rect)=minOf(a.bottom,b.bottom)-maxOf(a.top,b.top)>minOf(a.height,b.height)/2

    private fun scrollAudit(screen:String,container:String):Set<String> {
        val found=linkedSetOf<String>()
        repeat(14) { step ->
            ui.waitForIdle()
            found+=audit(screen)
            android.util.Log.i("KatUiAudit","$screen step $step: ${found.size} problems")
            if(step==0)screenshot("ui-audit-$screen.png")
            ui.onNodeWithTag(container).performTouchInput { swipeUp(startY=bottom*0.8f,endY=bottom*0.3f) }
        }
        return found
    }

    private fun screenshot(name:String) {
        val inst=InstrumentationRegistry.getInstrumentation()
        val bitmap=inst.uiAutomation.takeScreenshot() ?: return
        try { File(inst.targetContext.getExternalFilesDir(null),name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) } }
        finally { bitmap.recycle() }
    }

    @Test fun panelScreensAlignLineStartsInCards() {
        ui.runOnIdle { ViewModelProvider(ui.activity)[TranslatorState::class.java].changeInterfaceLanguage("ru") }
        val problems=mutableListOf<String>()
        ui.onNodeWithTag("toolbar.models").performClick()
        ui.waitUntil(10_000) { ui.onAllNodesWithTag("models.list").fetchSemanticsNodes().isNotEmpty() }
        problems+=scrollAudit("models","models.list")
        ui.onNodeWithTag("models.list").performScrollToNode(hasTestTag("models.languageSetup"))
        ui.onNodeWithTag("models.languageSetup").performClick()
        ui.waitUntil(30_000) { ui.onAllNodesWithTag("setup.download").fetchSemanticsNodes().isNotEmpty() }
        problems+=scrollAudit("setup","sheet.container")
        // "Later" returns to Models; close sheets until the main toolbar is reachable again.
        repeat(3) {
            if(ui.onAllNodesWithTag("toolbar.settings").fetchSemanticsNodes().isEmpty())ui.onNodeWithTag("sheet.close",useUnmergedTree=true).performClick()
            ui.waitForIdle()
        }
        ui.onNodeWithTag("toolbar.settings").performClick()
        ui.waitUntil(10_000) { ui.onAllNodesWithTag("sheet.container").fetchSemanticsNodes().isNotEmpty() }
        problems+=scrollAudit("settings","sheet.container")
        ui.onNodeWithTag("sheet.close",useUnmergedTree=true).performClick()
        ui.waitForIdle()
        problems.forEach { android.util.Log.i("KatUiAudit",it) }
        assertTrue(problems.joinToString("\n"),problems.isEmpty())
    }
}
