package org.openoffline.translator.android

import android.net.Uri
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

/** Opt-in full import benchmark; input, transcripts and audio remain in private cache. */
class StreamingLatencyTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun importAndDrain() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val args=InstrumentationRegistry.getArguments()
        org.junit.Assume.assumeTrue(args.getString("streamingLatency")=="true")
        val file=File(inst.targetContext.cacheDir,"asr-latency-input.wav")
        require(file.isFile)
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.changeMemorySaving(false);state.changeAutomaticSpeech(true)
            state.changeRecognitionPreference("whisper");state.selectRecognition("whisper-large-v3-turbo-q8_0")
            state.selectTranslation("opus");state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
            state.selectVoice("en","vits-piper-en_US-ljspeech-high")
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        val rows=JSONArray()
        try {
            repeat(args.getString("streamingRepeats","2")!!.toInt()) { index ->
                val start=System.nanoTime()
                ui.runOnUiThread { state.importAudio(Uri.fromFile(file)) }
                ui.waitUntil(180_000) { state.playing || (!state.busy && state.error!=null) }
                val first=(System.nanoTime()-start)/1e9
                ui.waitUntil(180_000) { !state.busy }
                val processed=(System.nanoTime()-start)/1e9
                ui.waitUntil(180_000) { !state.playing }
                ui.runOnIdle {
                    assertNull(state.error);assertTrue(state.hasTranslatedAudio)
                    val row=JSONObject().put("run",index).put("firstPlaybackSeconds",first)
                        .put("processedSeconds",processed).put("drainedSeconds",(System.nanoTime()-start)/1e9)
                        .put("recognitionSeconds",state.timing?.recognition).put("translationSeconds",state.timing?.translation)
                        .put("synthesisSeconds",state.timing?.synthesis).put("voiceLoadSeconds",state.speechRuntimeTiming?.load)
                    val metrics=requireNotNull(state.speechPlaybackMetrics)
                    assertNull(metrics.failure);assertTrue("Playback must drain to its final frame",metrics.completed)
                    assertEquals(metrics.written,metrics.played)
                    assertEquals("No buffer starvation during speech",0,metrics.underruns)
                    row.put("writtenFrames",metrics.written).put("playedFrames",metrics.played).put("underrunsBeforeDrain",metrics.underruns).put("underrunsAfterFinalWrite",metrics.drainUnderruns)
                        .put("firstWriteSeconds",(metrics.firstWriteNanos-start)/1e9)
                        .put("recognitionLoads",state.recognitionLoads).put("voiceLoads",state.voiceLoads)
                    if(index>0) { assertEquals(1,state.recognitionLoads);assertEquals(1,state.voiceLoads) }
                    rows.put(row)
                    File(inst.targetContext.cacheDir,"streaming-transcript-$index.txt").writeText(state.input)
                    File(inst.targetContext.cacheDir,"streaming-translation-$index.txt").writeText(state.output)
                    inst.sendStatus(0,android.os.Bundle().apply { putString("stream","\nSTREAMING_LATENCY $row\n") })
                }
                var exported:File?=null
                ui.runOnIdle { state.exportAudio(false) { exported=it } }
                ui.waitUntil(10_000) { exported!=null || !state.busy }
                requireNotNull(exported).let { assertEquals("Export and played frames must match",state.speechPlaybackMetrics!!.written,(it.length()-44)/2);it.copyTo(File(inst.targetContext.cacheDir,"streaming-output-$index.wav"),true);it.delete() }
                if(index==0 && args.getString("streamingGate")=="true") {
                    val ready=File(inst.targetContext.cacheDir,"streaming-ready")
                    val proceed=File(inst.targetContext.cacheDir,"streaming-continue")
                    proceed.delete();ready.writeText("ready")
                    val deadline=SystemClock.elapsedRealtime()+900_000
                    while(!proceed.exists() && SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(200)
                    check(proceed.exists()) { "Thermal continuation timed out" };ready.delete();proceed.delete()
                } else if(index==0)SystemClock.sleep(45_000)
            }
            File(inst.targetContext.cacheDir,"streaming-results.json").writeText(rows.toString(2))
        } finally { ui.runOnIdle { state.stopPlayback();if(state.busy)state.cancel() } }
    }
}
