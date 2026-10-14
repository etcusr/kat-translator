package org.openoffline.translator.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Real text, speech and photo pipelines. Remove only this test's new rows/files;
 * unlimited retention during the run protects every existing user entry. */
@RunWith(AndroidJUnit4::class)
class HistoryWorkspacesTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private lateinit var state:TranslatorState
    private var existing=setOf<String>()
    private fun setup() {
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java];existing=state.history.map { it.id }.toSet()
            state.setHistoryLimits(0,0);state.setMediaLimits("audio",0,0);state.setMediaLimits("image",0,0)
            state.setHistory(true);state.changeRecordAudio(true);state.changeRecordImages(true)
            state.selectTranslation("opus");state.chooseLanguage("en",false);state.chooseLanguage("ru",true)
            state.mode="voice";state.changeAutomaticSpeech(false);state.changeRecognitionPreference("automatic")
        }
        ui.waitUntil(30_000) { state.packages.restored.value }
    }
    private fun cleanup() { ui.runOnIdle {
        state.stopPlayback();state.history.filter { it.id !in existing }.forEach { state.deleteHistory(it.id) }
        state.resumeCamera();state.mode="voice"
    } }
    private fun completed() { ui.waitUntil(30_000) { !state.busy };ui.runOnIdle { assertNull(state.error) } }
    @Test fun voiceTextAndFrozenPhotoAppearPersistAndManualSpeechUpdatesSameRow() {
        setup()
        val inst=InstrumentationRegistry.getInstrumentation()
        val fixture=File(inst.targetContext.cacheDir,"history-voice-fixture.wav")
        inst.context.assets.open("media-asr-ru.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        val bitmap=Bitmap.createBitmap(1000,300,Bitmap.Config.ARGB_8888).apply {
            Canvas(this).apply { drawColor(Color.WHITE);drawText("HELLO WORLD",55f,160f,Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=66f }) }
        }
        try {
            ui.runOnIdle { state.importAudio(Uri.fromFile(fixture)) };completed()
            lateinit var voice:TranslationEntry
            ui.runOnIdle {
                voice=state.history.first { it.id !in existing }
                assertEquals("voice",voice.kind);assertTrue(voice.original.isNotBlank());assertTrue(voice.translated.isNotBlank())
                assertNotNull(state.historyFile(voice.originalAudio));assertNull(voice.audio)
                state.readText(false)
            };completed()
            ui.runOnIdle {
                state.stopPlayback();assertEquals(1,state.history.count { it.id !in existing })
                assertNotNull(state.historyFile(state.history.first { it.id==voice.id }.audio))
                state.mode="text";state.changeAutomaticSpeech(false);state.input="Спасибо за помощь.";state.translate()
            };completed()
            ui.runOnIdle {
                val text=state.history.first();assertEquals("text",text.kind);assertTrue(text.translated.isNotBlank());assertNull(text.originalAudio)
                state.chooseLanguage("ru",false);state.chooseLanguage("en",true)
                state.mode="camera";state.acceptCameraPhoto(bitmap)
            };completed()
            var ids=setOf<String>()
            ui.runOnIdle {
                val photo=state.history.first();assertEquals("camera",photo.kind);assertNotNull(state.historyFile(photo.image));assertTrue(photo.original.contains("HELLO",true))
                ids=state.history.filter { it.id !in existing }.map { it.id }.toSet();assertEquals(3,ids.size)
                state.resumeCamera();state.mode="voice"
            }
            ui.onNodeWithTag("toolbar.history").performClick()
            for(id in ids)ui.onNodeWithTag("history.list").performScrollToNode(hasTestTag("history.translation.$id"))
            ui.onNodeWithTag("sheet.close").performClick()
            // New ViewModel reads the persisted index rather than retaining Activity state.
            lateinit var restored:TranslatorState
            val store=androidx.lifecycle.ViewModelStore()
            ui.runOnIdle {
                restored=ViewModelProvider(store,ViewModelProvider.AndroidViewModelFactory(ui.activity.application))[TranslatorState::class.java]
                assertTrue(restored.history.map { it.id }.containsAll(ids));store.clear()
            }
        } finally { cleanup();fixture.delete();bitmap.recycle() }
    }
    @Test fun completedTextSurvivesSpeechFailureAndDisabledAudioDoesNotDuplicateHistory() {
        setup()
        try {
            ui.runOnIdle {
                state.mode="text";state.changeAutomaticSpeech(true);state.selectVoice("en","unavailable-test-voice")
                state.input="Доброе утро.";state.translate()
            }
            ui.waitUntil(30_000) { !state.busy }
            ui.runOnIdle {
                assertNotNull(state.error);val entry=state.history.first();assertEquals("text",entry.kind);assertTrue(entry.translated.isNotBlank())
                assertEquals(1,state.history.count { it.id !in existing })
                val english=state.packages.catalog.first { it.category==org.openoffline.translator.android.packages.PackageCategory.VOICE && it.supports("en") && state.packages.installedPath(it.id)!=null }
                state.selectVoice("en",english.id);state.changeRecordAudio(false);state.input="Спасибо.";state.translate()
            };completed()
            ui.runOnIdle { assertEquals(2,state.history.count { it.id !in existing });assertNull(state.history.first().audio);state.stopPlayback() }
            ui.runOnIdle { state.setHistory(false);state.changeAutomaticSpeech(false);state.input="До свидания.";state.translate() };completed()
            ui.runOnIdle { assertEquals("Disabled recording must remain respected",2,state.history.count { it.id !in existing }) }
        } finally { cleanup() }
    }
}
