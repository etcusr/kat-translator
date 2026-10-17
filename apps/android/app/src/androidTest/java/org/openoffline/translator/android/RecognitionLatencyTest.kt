package org.openoffline.translator.android

import android.net.Uri
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Opt-in real import pipeline. Private audio/text stays in app cache, never instrumentation logs. */
class RecognitionLatencyTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun profileWhisperImport() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val args=InstrumentationRegistry.getArguments()
        org.junit.Assume.assumeTrue("Opt in with -e recognitionLatency true",args.getString("recognitionLatency")=="true")
        val input=File(inst.targetContext.cacheDir,"asr-latency-input.wav")
        require(input.isFile && input.length() in 44..10_000_000)
        val model=args.getString("recognitionModel","whisper-large-v3-turbo-f16")!!
        require(model in setOf("whisper-large-v3-turbo-f16","whisper-large-v3-turbo-q8_0"))
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.changeMemorySaving(false)
            state.changeAutomaticSpeech(false);state.changeRecognitionPreference("whisper")
            state.selectRecognition(model)
            state.selectTranslation("opus");state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        try {
            ui.runOnUiThread { state.importAudio(Uri.fromFile(input)) }
            ui.waitUntil(180_000) { !state.busy }
            ui.runOnIdle {
                assertNull(state.error);assertEquals("whisper",state.recognitionBackend)
                assertTrue(state.input.isNotBlank());assertTrue(state.output.isNotBlank())
                args.getString("recognitionRuntime")?.let { assertEquals(it,state.recognitionRuntime) }
                val row=JSONObject().put("model",model)
                    .put("runtime",state.recognitionRuntime)
                    .put("recognitionSeconds",requireNotNull(state.timing?.recognition))
                    .put("translationSeconds",state.timing?.translation)
                    .put("totalSeconds",state.timing?.total)
                File(inst.targetContext.cacheDir,"asr-latency-results.json").writeText(row.toString(2))
                File(inst.targetContext.cacheDir,"asr-latency-transcript.txt").writeText(state.input)
                inst.sendStatus(0,android.os.Bundle().apply { putString("stream","\nRECOGNITION_LATENCY $row\n") })
            }
        } finally { ui.runOnIdle { state.stopPlayback();if(state.busy)state.cancel() } }
    }
}
