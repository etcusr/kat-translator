package org.openoffline.translator.android

import android.os.SystemClock
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Opt-in benchmark of the product path. Private input stays in cache; logs contain only timings. */
class SpeechLatencyTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun profileSelectedVoice() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val args=InstrumentationRegistry.getArguments()
        org.junit.Assume.assumeTrue("Opt in with -e speechLatency true",args.getString("speechLatency")=="true")
        val input=File(inst.targetContext.cacheDir,"tts-latency-input.txt").readText().trim()
        require(input.isNotBlank() && input.length<=1500)
        val language=args.getString("speechLanguage","en")!!
        val repeats=args.getString("speechRepeats","2")!!.toInt().also { require(it in 1..5) }
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.chooseLanguage(language,false)
            args.getString("speechVoice")?.let { state.selectVoice(language,it) }
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        val rows=JSONArray()
        try {
            repeat(repeats) { index ->
                ui.runOnIdle { state.clearOutput();state.output=input }
                val start=SystemClock.elapsedRealtime()
                ui.runOnUiThread { state.readText() }
                ui.waitUntil(120_000) { !state.busy }
                ui.runOnIdle {
                    assertNull(state.error);assertTrue(state.hasTranslatedAudio)
                    val native=requireNotNull(state.speechRuntimeTiming)
                    val total=requireNotNull(state.timing?.synthesis)
                    val row=JSONObject().put("run",index).put("voice",state.selectedVoice(language))
                        .put("characters",input.length).put("synthesisSeconds",total)
                        .put("wallSeconds",(SystemClock.elapsedRealtime()-start)/1000.0)
                        .put("loadSeconds",native.load).put("generateSeconds",native.generate)
                        .put("copySeconds",native.copy).put("releaseSeconds",native.release)
                        .put("otherSeconds",total-native.load-native.generate-native.copy-native.release)
                    rows.put(row);inst.sendStatus(0,android.os.Bundle().apply { putString("stream","\nSPEECH_LATENCY $row\n") })
                    state.stopPlayback()
                }
            }
            // Preserve the final product-normalized audio for optional external intelligibility checks.
            var exported:File?=null
            ui.runOnIdle { state.exportAudio(false) { exported=it } }
            ui.waitUntil(10_000) { exported!=null || !state.busy }
            requireNotNull(exported).let { file ->
                file.copyTo(File(inst.targetContext.cacheDir,"tts-latency-output.wav"),overwrite=true);file.delete()
            }
            File(inst.targetContext.cacheDir,"tts-latency-results.json").writeText(rows.toString(2))
        } finally { ui.runOnIdle { state.stopPlayback();if(state.busy)state.cancel() } }
    }
}
