package org.openoffline.translator.android

import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Real installed ASR/MT/TTS. Synthetic shared previews only; no user history writes. */
@RunWith(AndroidJUnit4::class)
class VoiceAutoRoutingTest {
    private val ui = createAndroidComposeRule<MainActivity>()
    @get:Rule val environment = UiTestEnvironment.wrap(ui)
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun report(text: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$text\n") })
    private fun prepare(): TranslatorState {
        lateinit var state: TranslatorState
        ui.runOnIdle {
            state = ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode = "voice"; state.setHistory(false); state.changeRecordAudio(false)
            state.changeAutomaticSpeech(true); state.changeMemorySaving(false)
            state.changeRecognitionPreference("automatic"); state.selectTranslation(AUTO_TRANSLATION)
        }
        ui.waitUntil(120_000) { state.packages.restored.value && state.deviceClass != null }
        ui.runOnIdle { assertFalse(state.strongDevice) }
        return state
    }
    private fun check(state: TranslatorState, language: String) {
        ui.runOnIdle {
            assertNull(state.error, state.error)
            assertEquals(language, state.detectedSource)
            assertEquals(if (language == "ru") "gigaam" else "parakeet", state.recognitionBackend)
            assertTrue(state.input, state.input.contains(if (language == "ru") "поезд" else "Zug", true))
            assertTrue(state.output, state.output.contains("train", true))
            assertTrue(state.hasOriginalAudio); assertTrue(state.hasTranslatedAudio)
            val field = TranslatorState::class.java.getDeclaredField("translationResources").apply { isAccessible = true }
            val resources = field.get(state) as TranslationResources<*, *>
            if (language == "ru") {
                assertNotNull(resources.opus); assertNotNull(resources.opusLease)
                assertNull(resources.index); assertNull(resources.indexLease)
            } else {
                assertNotNull(resources.index); assertNotNull(resources.indexLease)
                assertNull(resources.opus); assertNull(resources.opusLease)
            }
            report("KAT_PIXEL_VOICE_RESULT $language ${state.recognitionBackend} ${state.input} => ${state.output}")
        }
    }
    @Test fun importedSpeechSwitchesRealAsrAndAutoTranslation() {
        val state = prepare()
        for (language in listOf("ru", "de", "ru")) {
            val file = File.createTempFile("voice-auto-", ".m4a", ui.activity.cacheDir)
            try {
                ui.activity.assets.open("VoicePreviews/sherpa-onnx-supertonic-3-tts-int8-2026-05-11-$language.m4a").use { input -> file.outputStream().use { input.copyTo(it) } }
                ui.runOnIdle { state.chooseLanguage(language, true); state.chooseLanguage("en", false); state.importAudio(Uri.fromFile(file)) }
                ui.waitUntil(180_000) { !state.busy && (state.output.isNotBlank() || state.error != null) }
                check(state, language)
                ui.waitUntil(30_000) { !state.playing }
            } finally { file.delete() }
        }
        ui.runOnIdle { state.unload() }; ui.waitUntil(30_000) { !state.ready && !state.opusReady }
    }
    @Test fun microphoneSpeechSwitchesRealAsrAndAutoTranslation() {
        org.junit.Assume.assumeTrue("Opt-in coordinated peer speaker", InstrumentationRegistry.getArguments().getString("voicePeer") == "1")
        val state = prepare()
        for ((number, language) in listOf("ru", "de", "ru").withIndex()) {
            ui.runOnIdle {
                state.chooseLanguage(language, true); state.chooseLanguage("en", false)
                state.setSilence(30); state.changeRecordingPreprocessing(false); state.beginRecording()
                assertTrue(state.error, state.recording)
            }
            report("KAT_PIXEL_MIC_READY $number $language")
            Thread.sleep(25_000) // Host cues the iPhone speaker only after capture starts.
            ui.runOnIdle { assertTrue(state.recording); state.finishRecording() }
            ui.waitUntil(180_000) { !state.busy && (state.output.isNotBlank() || state.error != null) }
            check(state, language)
            ui.waitUntil(30_000) { !state.playing }
        }
        ui.runOnIdle { state.unload() }; ui.waitUntil(30_000) { !state.ready && !state.opusReady }
    }
}

/** Runs without the Activity/model store while the iPhone records the fixture. */
@RunWith(AndroidJUnit4::class)
class PeerVoiceSpeakerTest {
    @Test fun playSyntheticFixture() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val language = InstrumentationRegistry.getArguments().getString("language")
        org.junit.Assume.assumeTrue("Opt-in synthetic speaker: pass language=ru/de", language in setOf("ru", "de"))
        require(language in setOf("ru", "de"))
        val player = MediaPlayer()
        try {
            inst.targetContext.assets.openFd("VoicePreviews/sherpa-onnx-supertonic-3-tts-int8-2026-05-11-$language.m4a").use { player.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            player.setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH).build())
            player.prepare(); player.start()
            while (player.isPlaying) Thread.sleep(100)
        } finally { player.release() }
    }
}
