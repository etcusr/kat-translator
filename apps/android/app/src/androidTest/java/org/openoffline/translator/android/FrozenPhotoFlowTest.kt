package org.openoffline.translator.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog
import java.io.File

/** Real product OCR -> Index -> frozen-language reprocessing. Generated public text only;
 * no camera access, downloads, history files or public-gallery writes. Root runs alone. */
@RunWith(AndroidJUnit4::class)
class FrozenPhotoFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun generatedPhotoTranslatesAndLanguagePickerReprocessesSameImage() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val bitmap=Bitmap.createBitmap(900,300,Bitmap.Config.ARGB_8888).apply {
            Canvas(this).apply {
                drawColor(Color.WHITE)
                drawText("HELLO WORLD",50f,160f,Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=68f })
            }
        }
        var state:TranslatorState?=null
        var exported:File?=null
        fun awaitWork(model:TranslatorState) {
            var previous=""
            ui.waitUntil(600_000) {
                if(model.status!=previous) {
                    previous=model.status
                    instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nPHOTO stage: $previous\n") })
                }
                !model.busy
            }
            ui.runOnIdle { assertNull(model.error) }
        }
        try {
            ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java] }
            val model=requireNotNull(state)
            ui.waitUntil(180_000) { model.packages.restored.value && !model.busy }
            ui.runOnIdle {
                for(id in listOf(PackageCatalog.INDEX_ID,"ppocr-v5-det","ppocr-v5-english")) {
                    assertNotNull("Install exact shared fixture $id before running this test",model.packages.installedPath(id))
                }
                model.mode="text"
                model.setHistory(false);model.changeRecordAudio(false);model.changeRecordImages(false)
                model.changeAutomaticSpeech(false);model.selectTranslation("index")
                model.chooseLanguage("en",true);model.chooseLanguage("ru",false)
                model.mode="camera"
                model.acceptCameraPhoto(bitmap)
            }
            awaitWork(model)
            var russian=""
            ui.runOnIdle {
                assertSame("OCR must preserve the frozen source bitmap",bitmap,model.image)
                assertTrue(model.input,model.input.uppercase().contains("HELLO") && model.input.uppercase().contains("WORLD"))
                assertTrue("Detector must produce actual boxes",model.ocrBlocks.isNotEmpty())
                assertEquals(model.ocrBlocks.size,model.translatedBlocks.size)
                russian=model.output
                assertTrue("Expected Russian world in $russian",russian.contains("мир",true))
            }
            ui.onNodeWithTag("camera.frozen").assertIsDisplayed()
            ui.onNodeWithTag("language.target").performClick()
            ui.onNodeWithTag("language.search").performTextInput("de")
            ui.onNodeWithTag("language.list").performScrollToNode(hasTestTag("language.row.de"))
            ui.onNodeWithTag("language.row.de").performClick()
            ui.runOnIdle {
                assertEquals("de",model.target)
                assertEquals("en",model.source)
                assertSame(bitmap,model.image)
                assertTrue("Changing a frozen target must enqueue real OCR/translation",model.busy)
                assertTrue("Old-language overlay must be removed immediately",model.output.isEmpty())
            }
            awaitWork(model)
            ui.runOnIdle {
                assertNotEquals("Do not retain the prior Russian translation",russian,model.output)
                assertTrue("Expected German world in ${model.output}",model.output.contains("welt",true))
                assertEquals(model.ocrBlocks.size,model.translatedBlocks.size)
                assertTrue(model.translatedBlocks.all { it.isNotBlank() })
                model.exportPicture { exported=it }
            }
            awaitWork(model)
            val output=requireNotNull(exported) { "Missing actual translated PNG export" }
            assertTrue(output.length()>0)
            val decoded=requireNotNull(BitmapFactory.decodeFile(output.path))
            try {
                assertEquals(bitmap.width,decoded.width);assertEquals(bitmap.height,decoded.height)
                assertFalse("Export must contain the translated overlay",bitmap.sameAs(decoded))
            } finally { decoded.recycle() }
            instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nPHOTO PASS OCR=en, Index=ru then de, source bitmap preserved, private PNG overlay exported\n") })
        } finally {
            ui.runOnIdle { state?.let { model -> if(model.busy)model.cancel();model.stopPlayback();model.mode="camera";model.clear();model.mode="text" } }
            state?.let { model -> ui.waitUntil(120_000) { !model.busy } }
            ui.waitForIdle()
            exported?.delete();bitmap.recycle()
        }
    }
}
