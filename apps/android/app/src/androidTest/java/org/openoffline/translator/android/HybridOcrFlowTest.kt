package org.openoffline.translator.android

import android.graphics.*
import android.os.Bundle
import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HybridOcrFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun englishPhotoUsesBundledMlKitAndTranslatesWithOpus()=photo("en","ru","HELLO WORLD","мир","Google ML Kit")
    @Test fun russianPhotoUsesOpenOcrAndTranslatesWithOpus()=photo("ru","en","ПРИВЕТ МИР","world","PP-OCR")

    private fun photo(source:String,target:String,text:String,expected:String,backend:String) {
        val bitmap=Bitmap.createBitmap(1000,300,Bitmap.Config.ARGB_8888).apply {
            Canvas(this).apply { drawColor(Color.WHITE);drawText(text,55f,160f,Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=66f }) }
        }
        lateinit var state:TranslatorState
        try {
            ui.runOnIdle {
                state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
                state.mode="text";state.setHistory(false);state.changeRecordImages(false);state.changeAutomaticSpeech(false)
                state.selectTranslation("opus");state.chooseLanguage(target,false);state.chooseLanguage(source,true)
                state.mode="camera"
            }
            ui.waitUntil(30_000) { state.packages.restored.value }
            val start=SystemClock.elapsedRealtime()
            ui.runOnUiThread { state.acceptCameraPhoto(bitmap) }
            ui.waitUntil(30_000) { !state.busy }
            ui.runOnIdle {
                assertNull(state.error);assertEquals(text,state.input.uppercase())
                assertTrue(state.cameraNotice.orEmpty(),state.cameraNotice.orEmpty().contains(backend))
                assertTrue(state.output,state.output.contains(expected,true))
                assertTrue(state.ocrBlocks.isNotEmpty());assertEquals(state.ocrBlocks.size,state.translatedBlocks.size)
                assertFalse("OPUS must not allocate Index",state.ready)
                assertSame(bitmap,state.image)
                assertNotNull(state.timing?.recognition);assertNotNull(state.timing?.translation);assertNull(state.timing?.synthesis)
                assertTrue(state.timing!!.total>=state.timing!!.recognition!!+state.timing!!.translation!!)
            }
            ui.onNodeWithTag("camera.frozen").assertIsDisplayed()
            InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply { putString("stream","\nHYBRID_OCR source=$source backend=$backend photo+OPUS=${SystemClock.elapsedRealtime()-start}ms output=${state.output}\n") })
        } finally { ui.runOnIdle { state.resumeCamera();state.mode="text" };bitmap.recycle() }
    }
    @Test fun cameraAndSpeechHaveExplicitSourceWhileTextCanDetectLanguage() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="text";state.chooseLanguage("en",false);state.chooseLanguage("ru",true);state.chooseLanguage("auto",true)
            state.mode="camera"
            assertEquals("ru",state.currentSource);assertEquals("auto",state.source)
        }
        ui.onNodeWithTag("language.source").performClick()
        ui.onNodeWithTag("language.row.auto").assertDoesNotExist()
        ui.runOnIdle {
            state.chooseLanguage("auto",true)
            assertEquals("ru",state.currentSource)
        }
        androidx.test.espresso.Espresso.pressBack()
        ui.runOnIdle { state.mode="voice";assertEquals("ru",state.currentSource) }
        ui.onNodeWithTag("language.source").performScrollTo().performClick()
        ui.onNodeWithTag("language.row.auto").assertDoesNotExist()
        androidx.test.espresso.Espresso.pressBack()
        ui.runOnIdle { state.mode="text";assertEquals("auto",state.currentSource) }
        ui.onNodeWithTag("language.source").performScrollTo().performClick()
        ui.onNodeWithTag("language.row.auto").assertIsDisplayed()
    }
}
