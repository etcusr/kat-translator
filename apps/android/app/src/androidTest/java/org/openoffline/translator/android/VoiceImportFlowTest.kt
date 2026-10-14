package org.openoffline.translator.android

import android.net.Uri
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Real imported recording -> Whisper -> unchanged Index -> Supertonic.
 * Root runs this alone after installing exact shared fixtures. */
@RunWith(AndroidJUnit4::class)
class VoiceImportFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun realImportedVoiceProducesTranslationAndBothAudioExports() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val context=inst.targetContext
        val prefs=context.getSharedPreferences("kat",0)
        val before=prefs.all.toMap()
        val fixture=File(context.cacheDir,"voice-import-acceptance.wav")
        inst.context.assets.open("media-asr-en.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        lateinit var state:TranslatorState
        var stateInitialized=false
        val exports=mutableListOf<File>()
        try {
            ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java];stateInitialized=true }
            ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
            ui.runOnIdle {
                state.mode="voice"
                state.setHistory(false);state.changeRecordAudio(false);state.changeRecordImages(false)
                state.selectTranslation("index")
                state.selectRecognition("whisper-large-v3-turbo-f16")
                state.selectVoice("ru","sherpa-onnx-supertonic-3-tts-int8-2026-05-11")
                state.chooseLanguage("en",true);state.chooseLanguage("ru",false)
                state.changeAutomaticSpeech(true)
                state.importAudio(Uri.fromFile(fixture))
            }
            var lastStage=""
            ui.waitUntil(600_000) {
                if(state.status!=lastStage) {
                    lastStage=state.status
                    inst.sendStatus(0,android.os.Bundle().apply { putString("stream","\nVoice stage: $lastStage\n") })
                }
                !state.busy
            }
            ui.runOnIdle {
                assertNull(state.error)
                assertTrue(state.input,state.input.contains("cancel",true))
                assertTrue(state.output,state.output.contains("заказ",true))
                assertTrue("Actual imported recording must remain replayable",state.hasOriginalAudio)
                assertTrue("Completed translation must have real speech",state.hasTranslatedAudio)
                state.stopPlayback()
            }
            for(original in listOf(true,false)) {
                var result:File?=null
                ui.runOnIdle { state.exportAudio(original) { result=it } }
                ui.waitUntil(30_000) { result!=null || !state.busy }
                ui.runOnIdle {
                    assertNull(state.error)
                    val file=requireNotNull(result) { "Audio export callback missing" }
                    exports+=file
                    assertTrue(file.length()>44)
                    assertEquals("RIFF",file.inputStream().use { input -> val header=ByteArray(4);assertEquals(4,input.read(header));String(header,Charsets.US_ASCII) })
                }
            }
            assertNotEquals("Original and synthesized recording are separate exports",exports[0].readBytes().contentHashCode(),exports[1].readBytes().contentHashCode())
        } finally {
            ui.runOnIdle { if(stateInitialized) { state.stopPlayback();if(state.busy)state.cancel() } }
            // Restore only keys changed by this test; retain concurrent verification receipts.
            val keys=listOf("historyRecordText","historyRecordAudio","historyRecordImages","translationModel","recognitionModel","voice.ru","source","target","manualSource","automaticSpeech","automaticSpeechVoice","automaticSpeechText")
            prefs.edit().apply {
                for(key in keys)when(val value=before[key]) {
                    null -> remove(key)
                    is Boolean -> putBoolean(key,value)
                    is String -> putString(key,value)
                }
            }.commit()
            exports.forEach { it.delete() };fixture.delete()
        }
    }
}
