package org.openoffline.translator.android

import android.net.Uri
import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCategory
import java.io.File

@RunWith(AndroidJUnit4::class)
class OriginalRecordingActionsTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    @Test fun originalSpeakerUsesRecordingAndExportOnlyAdjustsLoudness() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val fixture=File(inst.targetContext.cacheDir,"original-actions.wav")
        inst.context.assets.open("media-asr-ru.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        // Quiet real speech, matching Pixel's low VOICE_RECOGNITION capture level.
        val quiet=AudioImport.decode(inst.targetContext,Uri.fromFile(fixture)) { false }.map { it*.125f }.toFloatArray()
        org.openoffline.translator.inference.SpeechPlayer.writeWav(fixture,org.openoffline.translator.inference.SpeechAudio(quiet,16000))
        lateinit var state:TranslatorState
        var exported:File?=null
        try {
            ui.runOnIdle {
                state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
                state.mode="voice";state.setHistory(false);state.changeRecordAudio(false);state.changeAutomaticSpeech(false)
                state.selectTranslation("opus");state.chooseLanguage("en",false);state.chooseLanguage("ru",true)
                state.changeRecognitionPreference("automatic")
            }
            ui.waitUntil(30_000) { state.packages.restored.value }
            ui.runOnUiThread { state.importAudio(Uri.fromFile(fixture)) }
            ui.waitUntil(25_000) { !state.busy }
            ui.runOnIdle {
                assertNull(state.error);assertTrue(state.hasOriginalAudio)
                // Deliberately invalid selected TTS model: source playback must not consult it.
                state.selectVoice("ru","missing-voice-test")
                state.input="Этот изменённый текст нельзя синтезировать вместо записи."
            }
            ui.onNodeWithTag("text.source.playback").performScrollTo()
                .assertContentDescriptionEquals("Прослушать запись").performClick()
            ui.waitUntil(2_000) { state.playing || state.error!=null }
            val decoded=AudioImport.decode(inst.targetContext,Uri.fromFile(fixture)) { false }
            val expectedGain=org.openoffline.translator.inference.SpeechLoudness.recordingGain(decoded,16000) ?: 1.0
            assertTrue("Quiet microphone speech needs more than the old 4x cap",expectedGain>4.0)
            ui.waitUntil(2_000) { kotlin.math.abs(state.playbackGain-expectedGain)<1e-6 }
            ui.runOnIdle { assertNull(state.error);assertTrue(state.playing);assertFalse(state.busy)
                assertNotNull(state.timing?.recognition);assertNotNull(state.timing?.translation)
                assertTrue(state.timing!!.total>=state.timing!!.recognition!!+state.timing!!.translation!!)
                state.mode="text";assertNull(state.timing);state.mode="voice"
            }
            ui.onNodeWithTag("text.source.playback").performClick()
            ui.runOnIdle { assertFalse(state.playing) }
            ui.onNodeWithTag("text.share.source").assertContentDescriptionEquals("Поделиться записью")
            ui.onAllNodesWithText("Прослушать запись").assertCountEquals(0)
            ui.onAllNodesWithText("Поделиться записью").assertCountEquals(0)
            val captured=java.util.concurrent.atomic.AtomicReference<android.content.Intent>()
            val monitor=object:android.app.Instrumentation.ActivityMonitor() {
                override fun onStartActivity(intent:android.content.Intent):android.app.Instrumentation.ActivityResult? {
                    if(intent.action!=android.content.Intent.ACTION_CHOOSER)return null
                    captured.set(intent);return android.app.Instrumentation.ActivityResult(0,null)
                }
            }
            inst.addMonitor(monitor)
            try {
                ui.onNodeWithTag("text.share.source").performClick()
                ui.waitUntil(5_000) { captured.get()!=null && !state.busy }
                val send=captured.get().getParcelableExtra<android.content.Intent>(android.content.Intent.EXTRA_INTENT)!!
                assertEquals("audio/wav",send.type)
                assertEquals(android.content.Intent.ACTION_SEND,send.action)
                val uri=send.getParcelableExtra<Uri>(android.content.Intent.EXTRA_STREAM)!!
                exported=File(inst.targetContext.cacheDir,"shared-original-check.wav")
                inst.targetContext.contentResolver.openInputStream(uri)!!.use { input -> exported!!.outputStream().use { input.copyTo(it) } }
                inst.targetContext.contentResolver.delete(uri,null,null)
            } finally { inst.removeMonitor(monitor) }
            val original=org.openoffline.translator.android.AudioImport.decode(inst.targetContext,Uri.fromFile(fixture)) { false }
            // Read delivered PCM directly: AudioImport would quantize it a second time into its spool.
            val wav=java.nio.ByteBuffer.wrap(exported!!.readBytes()).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            assertEquals(16000,wav.getInt(24));assertEquals(1,wav.getShort(22).toInt())
            wav.position(44)
            val actual=FloatArray(wav.remaining()/2) { wav.short/32768f }
            assertEquals(original.size,actual.size)
            val normalized=org.openoffline.translator.inference.SpeechLoudness.normalizeRecording(org.openoffline.translator.inference.SpeechAudio(original,16000))
            for(i in original.indices)assertEquals("Original recording with bounded loudness adjustment, sample $i",normalized.samples[i],actual[i],2f/32768)
            ui.runOnIdle {
                state.openHistory(TranslationEntry("no-recording","Старая запись","Old recording","en",0,"ru","voice"))
                assertFalse("History without an audio file must not replay the previous recording",state.hasOriginalAudio)
                state.readText(true);assertFalse(state.playing);assertFalse(state.busy)
            }
        } finally { ui.runOnIdle { state.stopPlayback() };fixture.delete();exported?.delete() }
    }

    @Test fun translatedAudioIsSharedOnlyFromTranslationPanel() {
        val inst=InstrumentationRegistry.getInstrumentation()
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="voice";state.setHistory(false);state.changeRecordAudio(false)
            state.chooseLanguage("en",false);state.input="Доброе утро.";state.output="Good morning."
        }
        ui.waitUntil(30_000) { state.packages.restored.value }
        ui.onNodeWithTag("voice.share.translation").assertDoesNotExist()
        ui.onNodeWithText("Поделиться аудио перевода").assertDoesNotExist()
        ui.onNodeWithTag("text.share.target").performScrollTo().assertIsNotEnabled()
        ui.runOnIdle { state.readText(false) }
        ui.waitUntil(30_000) { !state.busy }
        ui.runOnIdle { assertNull(state.error);assertTrue(state.hasTranslatedAudio);assertNotNull(state.timing?.synthesis);assertTrue(state.timing!!.total>=state.timing!!.synthesis!!);state.stopPlayback() }
        var chooser:android.content.Intent?=null
        val monitor=object:android.app.Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent:android.content.Intent):android.app.Instrumentation.ActivityResult? {
                if(intent.action!=android.content.Intent.ACTION_CHOOSER)return null
                chooser=intent;return android.app.Instrumentation.ActivityResult(android.app.Activity.RESULT_CANCELED,null)
            }
        }
        inst.addMonitor(monitor)
        try {
            ui.onNodeWithTag("text.share.target").performScrollTo().assertContentDescriptionEquals("Поделиться аудио перевода").performClick()
            ui.waitUntil(5_000) { chooser!=null }
            val send=chooser!!.getParcelableExtra<android.content.Intent>(android.content.Intent.EXTRA_INTENT)!!
            assertEquals("audio/wav",send.type)
            val uri=send.getParcelableExtra<Uri>(android.content.Intent.EXTRA_STREAM)!!
            inst.targetContext.contentResolver.openInputStream(uri)!!.use { assertTrue(it.readBytes().size>44) }
            inst.targetContext.contentResolver.delete(uri,null,null)
        } finally { inst.removeMonitor(monitor);ui.runOnIdle { state.stopPlayback() } }
    }

    @Test fun absentEnglishVoiceNoticeStartsDownloadAndShowsProgress() {
        var clicks=0
        val status=androidx.compose.runtime.mutableStateOf(org.openoffline.translator.android.packages.PackageStatus())
        ui.runOnUiThread { ui.activity.setContent {
            androidx.compose.runtime.CompositionLocalProvider(LocalUiLanguage provides "ru") {
                VoiceDownloadNotice("Английский",status.value) { clicks++ }
            }
        } }
        ui.onNodeWithText("Озвучка для языка «Английский» не скачана. Нажмите, чтобы скачать.").assertIsDisplayed()
        ui.onNodeWithTag("voice.download.notice").performClick()
        assertEquals(1,clicks)
        ui.runOnIdle { status.value=org.openoffline.translator.android.packages.PackageStatus(org.openoffline.translator.android.packages.PackagePhase.DOWNLOADING,50,100) }
        ui.onNodeWithTag("voice.download.notice").assertIsNotEnabled()
        ui.onNodeWithText("Скачиваю озвучку: Английский · 50%").assertIsDisplayed()
    }
}
