package org.openoffline.translator.android

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Bundle
import android.os.SystemClock
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import java.io.File

/** Opt-in: plays a WAV from the app cache through the phone's own speaker while the real microphone recording
 * (live phrase preview) runs. Arguments: wav, source, target, verify (default false). Prints a timeline only.
 * The test rule restores the owner's preferences; history recording is disabled for the run. */
@RunWith(AndroidJUnit4::class)
class LiveSpeakerProbe {
    private val ui = createAndroidComposeRule<MainActivity>()
    @get:Rule val environment = UiTestEnvironment.wrap(ui)
    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private fun report(text: String) = inst.sendStatus(0, Bundle().apply { putString("stream", "\nLIVE $text\n") })

    @Test fun speakIntoMicrophone() {
        val args = InstrumentationRegistry.getArguments()
        val name = args.getString("wav"); assumeTrue("wav argument required", name != null)
        val source = args.getString("source") ?: "en"; val target = args.getString("target") ?: "ru"
        val verify = args.getString("verify") == "true"
        lateinit var state: TranslatorState
        ui.runOnIdle {
            state = ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode = "voice"; state.setHistory(false); state.changeRecordAudio(false)
            state.changeAutomaticSpeech(false); state.changeMemorySaving(false)
        }
        ui.waitUntil(120_000) { state.packages.restored.value && state.deviceClass != null }
        ui.runOnIdle {
            state.chooseLanguage(source, true); state.chooseLanguage(target, false)
            state.setSilence(30); state.changeRecordingPreprocessing(true); state.changeRecordingVerification(verify)
        }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { if (!state.voiceReady) state.prepare() }
        ui.waitUntil(300_000) { state.voiceReady && !state.busy }
        ui.runOnIdle { state.beginRecording() }
        val start = SystemClock.elapsedRealtime()
        fun t() = "%.1f".format((SystemClock.elapsedRealtime() - start) / 1000.0)
        Thread.sleep(800)
        val player = MediaPlayer()
        var lastOut = ""
        try {
            player.setDataSource(File(ui.activity.cacheDir, name!!).path)
            player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            player.prepare(); player.start(); report("${t()} playback start")
            while (player.isPlaying) {
                Thread.sleep(250)
                ui.runOnIdle { if (state.output != lastOut) { lastOut = state.output; report("${t()} output: $lastOut") } }
            }
            report("${t()} playback end")
        } finally { player.release() }
        Thread.sleep(1500)
        ui.runOnIdle { report("${t()} stop; source so far: ${state.input}"); state.finishRecording() }
        val stopped = SystemClock.elapsedRealtime()
        ui.waitUntil(300_000) { !state.busy && !state.recording }
        ui.runOnIdle {
            report("after stop %.2f s; backend=${state.recognitionBackend} error=${state.error}".format((SystemClock.elapsedRealtime() - stopped) / 1000.0))
            report("final source: ${state.input}"); report("final translation: ${state.output}")
        }
    }
}
