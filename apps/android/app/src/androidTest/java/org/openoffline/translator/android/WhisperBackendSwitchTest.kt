package org.openoffline.translator.android

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.openoffline.translator.inference.OfflineMedia
import java.io.File
import java.util.concurrent.CancellationException

/** Opt-in native model ownership check; cancel after loading to isolate create/free from inference. */
class WhisperBackendSwitchTest {
    @Test fun q8AndF16HandlesAreReleasedByTheirOwnLibraries() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("whisperBackendSwitch")=="true")
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val packages=File(context.getExternalFilesDir(null),"packages")
        // Single-file packages use their catalog ID locally, not the upstream download basename.
        val q8=File(packages,"whisper-large-v3-turbo-q8_0/ggml-large-v3-turbo-q8_0.bin")
        val f16=File(packages,"whisper-large-v3-turbo-f16.bin")
        require(q8.isFile && f16.isFile) { "Install both Whisper Q8 and F16 before this opt-in test" }
        OfflineMedia().use { media ->
            for((index,pair) in listOf(q8 to "i8mm",f16 to "arm82",q8 to "i8mm").withIndex()) {
                var checks=0
                assertThrows(CancellationException::class.java) {
                    media.transcribe(pair.first.path,FloatArray(16000){.01f},"ru") { checks++>0 }
                }
                assertEquals(pair.second,media.recognitionRuntime)
                assertEquals(index+1,media.recognitionLoads)
            }
            media.releaseRecognition();assertNull(media.recognitionRuntime)
            media.releaseRecognition();assertEquals(3,media.recognitionLoads)
        }
    }
}
