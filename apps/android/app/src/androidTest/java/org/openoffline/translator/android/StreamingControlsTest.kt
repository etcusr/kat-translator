package org.openoffline.translator.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Opt-in real selected voice; stop while native synthesis is still producing callbacks. */
class StreamingControlsTest {
    private val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun stopDuringGenerationThenReplayAndUnload() {
        val inst=InstrumentationRegistry.getInstrumentation()
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("streamingLatency")=="true")
        val text=File(inst.targetContext.cacheDir,"tts-latency-input.txt").readText()
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.changeMemorySaving(false);state.chooseLanguage("en",false)
            state.selectVoice("en","vits-piper-en_US-ljspeech-high");state.output=text
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        try {
            ui.runOnUiThread { state.readText() }
            ui.waitUntil(60_000) { state.isTextPlaying() }
            ui.runOnIdle { assertTrue("First audio should precede the end of synthesis",state.busy);state.readText();assertFalse(state.playing) }
            ui.waitUntil(60_000) { !state.busy }
            ui.runOnIdle { assertNull(state.error);assertFalse("Late callback must not restart playback",state.playing);assertTrue(state.hasTranslatedAudio);state.readText() }
            ui.waitUntil(60_000) { !state.playing }
            ui.runOnIdle {
                val p=requireNotNull(state.speechPlaybackMetrics)
                assertTrue(p.completed);assertEquals(p.written,p.played);assertNull(p.failure)
                assertEquals("Replay must reuse stored audio",1,state.voiceLoads)
                state.unload()
            }
            // The next queued operation follows unload on the same owner executor.
            ui.runOnIdle { state.clearOutput();state.output=text;state.readText() }
            ui.waitUntil(60_000) { !state.busy }
            ui.runOnIdle { assertNull(state.error);assertEquals("Explicit unload must release the voice",2,state.voiceLoads);state.stopPlayback() }
        } finally { ui.runOnIdle { state.cancel();state.stopPlayback() } }
    }
    @Test fun cancelledWhisperCanBeReusedThenReleasedUnderMemoryPressure() {
        val inst=InstrumentationRegistry.getInstrumentation()
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("streamingLatency")=="true")
        val input=File(inst.targetContext.cacheDir,"asr-latency-input.wav")
        val expected=File(inst.targetContext.cacheDir,"streaming-transcript-0.txt").readText()
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.changeMemorySaving(false);state.changeAutomaticSpeech(false)
            state.selectRecognition("whisper-large-v3-turbo-q8_0")
            state.selectTranslation("opus");state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        try {
            ui.runOnUiThread { state.importAudio(android.net.Uri.fromFile(input)) }
            ui.waitUntil(10_000) { state.hasOriginalAudio && state.busy }
            android.os.SystemClock.sleep(5000)
            ui.runOnIdle { assertTrue(state.busy);state.cancel() }
            ui.waitUntil(10_000) { !state.busy }
            ui.runOnIdle { assertEquals("",state.input) }
            repeat(2) { index ->
                ui.runOnUiThread { state.importAudio(android.net.Uri.fromFile(input)) }
                ui.waitUntil(180_000) { !state.busy }
                ui.runOnIdle {
                    assertNull(state.error);assertEquals(expected,state.input)
                    assertEquals(index+1,state.recognitionLoads)
                    if(index==0)state.trimMemory()
                }
            }
        } finally { ui.runOnIdle { state.cancel();state.stopPlayback() } }
    }
    @Test fun shortOpeningPunctuationAndNumbersDrainOnce() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("streamingLatency")=="true")
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false);state.changeMemorySaving(false)
            state.chooseLanguage("en",false);state.selectVoice("en","vits-piper-en_US-ljspeech-high")
        }
        ui.waitUntil(180_000) { state.packages.restored.value && !state.busy }
        try {
            for(text in listOf("Yes. ... Is it ready?!\nThe train leaves at 12:45 on May 7th. End of the test.","1, 2, 3. 10, 20, 30. 100.","Hello.")) {
                ui.runOnIdle { state.clearOutput();state.output=text;state.readText() }
                ui.waitUntil(60_000) { !state.busy }
                ui.waitUntil(60_000) { !state.playing }
                ui.runOnIdle {
                    assertNull(state.error);assertTrue(state.hasTranslatedAudio)
                    val p=requireNotNull(state.speechPlaybackMetrics)
                    assertTrue(p.completed);assertEquals(p.written,p.played);assertNull(p.failure)
                    assertEquals(0,p.underruns)
                }
            }
        } finally { ui.runOnIdle { state.cancel();state.stopPlayback() } }
    }
}
