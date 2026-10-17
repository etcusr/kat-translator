package org.openoffline.translator.android

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.openoffline.translator.inference.OfflineMedia
import java.io.File
import java.util.concurrent.CancellationException

/** Existing installed models only; no capture, text generation, history, settings or downloads. */
class RecognitionPreloadDeviceTest {
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private val packages get()=File(inst.targetContext.getExternalFilesDir(null),"packages")
    @Test fun systemServiceChecksInstalledLanguagesAndRecoversAfterCancelledPreparation() {
        SystemSpeechRecognizer(inst.targetContext).use { service ->
            assertThrows(CancellationException::class.java) { service.prepare("ru") { true } }
            for(language in InstrumentationRegistry.getArguments().getString("languages","ru,en").split(",")) {
                val start=SystemClock.elapsedRealtimeNanos()
                service.prepare(language) { false }
                inst.sendStatus(0,Bundle().apply { putString("stream","\nSYSTEM_ASR_READY language=$language seconds=${(SystemClock.elapsedRealtimeNanos()-start)/1e9}\n") })
                service.releasePrepared()
            }
        }
        inst.waitForIdleSync()
    }
    @Test fun gigaamParakeetAndOmniPreloadReuseAndReleaseTheirOwnModels() {
        val giga=File(packages,"gigaam-v3-int8")
        val parakeet=File(packages,"parakeet-v3-int8")
        val omni=File(packages,"sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-v2-int8-2026-02-05")
        val model=omni.walkTopDown().first { it.isFile && it.extension=="onnx" }
        val tokens=omni.walkTopDown().first { it.isFile && it.name=="tokens.txt" }
        OfflineMedia().use { media ->
            val cases=listOf<Pair<String,()->Unit>>(
                "gigaam" to { media.preloadNemo(giga.path,false) },
                "parakeet" to { media.preloadNemo(parakeet.path,true) },
                "omnilingual" to { media.preloadOmnilingual(model.path,tokens.path) })
            var expectedLoads=0
            for((name,load) in cases) {
                val start=SystemClock.elapsedRealtimeNanos();load();expectedLoads++
                inst.sendStatus(0,Bundle().apply { putString("stream","\nASR_PRELOAD backend=$name seconds=${(SystemClock.elapsedRealtimeNanos()-start)/1e9}\n") })
                assertEquals(name,media.recognitionRuntime);assertEquals(expectedLoads,media.recognitionLoads)
                load();assertEquals(expectedLoads,media.recognitionLoads)
                media.releaseRecognition();assertNull(media.recognitionRuntime)
                load();expectedLoads++;assertEquals(expectedLoads,media.recognitionLoads)
            }
            media.releaseRecognition();media.releaseRecognition();assertNull(media.recognitionRuntime)
            assertThrows(CancellationException::class.java) { media.preloadNemo(giga.path,false) { true } }
            assertNull(media.recognitionRuntime)
            media.preloadNemo(giga.path,false);assertEquals("gigaam",media.recognitionRuntime)
        }
    }
}
