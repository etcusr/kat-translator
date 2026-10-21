package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import androidx.compose.runtime.MutableState
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.PcmRecorder
import java.io.File

/** Silent device regression: real decoded PCM, ASR and Index2B through import and
 * finishRecording. Test-only injection supplies already captured samples; this is
 * NOT a microphone/AudioRecord acceptance test. No production injection API. */
@RunWith(AndroidJUnit4::class)
class UnifiedRecognitionFlowTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private fun report(value:String)=inst.sendStatus(0,Bundle().apply { putString("stream","\nUNIFIED_ASR $value\n") })
    private fun words(text:String)=text.lowercase().filter { it.isLetterOrDigit() }
    private fun setField(owner:Any,name:String,value:Any?) {
        owner.javaClass.getDeclaredField(name).apply { isAccessible=true }.set(owner,value)
    }
    private fun liveId(state:TranslatorState,language:String):String? =
        state.javaClass.getDeclaredMethod("liveRecognition",String::class.java).apply { isAccessible=true }.invoke(state,language) as String?

    @Suppress("UNCHECKED_CAST")
    private fun finishSamples(state:TranslatorState,samples:FloatArray,language:String,session:RecordingPreview?) {
        val recorder=state.javaClass.getDeclaredMethod("getRecorder").apply { isAccessible=true }.invoke(state) as PcmRecorder
        assertFalse(recorder.isRecording)
        setField(recorder,"lastSamples",samples)
        setField(recorder,"lastSpeechMillis",samples.size/16L)
        setField(state,"activeRecordingSource",language)
        setField(state,"activeRecordingTarget",if(language=="ru")"en" else "ru")
        setField(state,"activeRecordingSpeak",false)
        setField(state,"recordingPreview",session)
        val recording=state.javaClass.getDeclaredField("recording\$delegate").apply { isAccessible=true }.get(state) as MutableState<Boolean>
        recording.value=true
        state.finishRecording()
    }

    @Test fun importAndEveryRecordingFinishPathUseTheSameLanguageModel() {
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.changeAutomaticSpeech(false);state.changeMemorySaving(false)
            state.changeRecognitionPreference("automatic");state.selectTranslation("index2b")
        }
        ui.waitUntil(120_000) { state.packages.restored.value && state.deviceClass!=null }
        for((language,id) in listOf("ru" to "gigaam-v3-int8","en" to "parakeet-v2-en-int8")) {
            val backend=if(language=="ru")"gigaam" else "parakeet"
            val file=File(inst.targetContext.cacheDir,"routing-$language.wav")
            assertTrue("Provide a public speech fixture in cache/routing-$language.wav",file.isFile)
            val samples=AudioImport.decode(inst.targetContext,Uri.fromFile(file)) { false }
            ui.runOnIdle {
                state.mode="text";state.chooseLanguage(language,true);state.chooseLanguage(if(language=="ru")"en" else "ru",false);state.mode="voice"
                assertEquals(id,state.automaticRecognitionPackage!!.id)
                assertEquals(id,liveId(state,language))
            }
            ui.waitUntil(30_000) { !state.busy }
            ui.runOnIdle { state.importAudio(Uri.fromFile(file)) }
            ui.waitUntil(180_000) { !state.busy }
            var imported=""
            ui.runOnIdle {
                assertNull(state.error);assertEquals(backend,state.recognitionBackend)
                assertEquals("index2b",state.effectiveModel);assertTrue(state.output.isNotBlank())
                assertTrue(state.input.isNotBlank());imported=words(state.input)
                report("$language import package=$id backend=${state.recognitionBackend} asr=${state.timing?.recognition}")
            }
            for(path in listOf("no-preview","unverified-tail","full-verification")) {
                val session=if(path=="no-preview")null else RecordingPreview(language,if(language=="ru")"en" else "ru",
                    verify=path=="full-verification",speak=false,punctuated=language!="ru",recognizer=id)
                // Verification must discard provisional output and re-run the entire PCM
                // through the same selected model, not keep the provisional ledger.
                if(path=="full-verification")assertTrue(session!!.commit(0 until samples.size,"Discard this provisional sentence.","Discard this provisional translation.",language))
                ui.runOnIdle { finishSamples(state,samples,language,session) }
                ui.waitUntil(180_000) { !state.busy && !state.recording }
                ui.runOnIdle {
                    assertNull(state.error);assertEquals(backend,state.recognitionBackend)
                    assertEquals(imported,words(state.input));assertTrue(state.output.isNotBlank())
                    assertFalse(state.output.contains("Discard this"));assertEquals("index2b",state.effectiveModel)
                    report("$language $path package=$id backend=${state.recognitionBackend} asr=${state.timing?.recognition}")
                }
            }
        }
        ui.runOnIdle {
            state.mode="text";state.chooseLanguage("de",true);state.chooseLanguage("ru",false);state.mode="voice"
            assertEquals("whisper-large-v3-turbo-q8_0",state.automaticRecognitionPackage!!.id)
            assertEquals("whisper-large-v3-turbo-q8_0",liveId(state,"de"))
            // Manual choices remain explicit and consistent rather than being silently
            // overridden in live recording as before this fix.
            state.selectRecognition("whisper-large-v3-turbo-q8_0")
            assertEquals("whisper-large-v3-turbo-q8_0",liveId(state,"ru"))
            assertEquals("whisper-large-v3-turbo-q8_0",liveId(state,"en"))
            state.changeRecognitionPreference("system");assertNull(liveId(state,"ru"))
        }
    }
}
