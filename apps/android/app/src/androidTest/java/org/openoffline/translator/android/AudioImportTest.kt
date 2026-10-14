package org.openoffline.translator.android

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.SpeechAudio
import org.openoffline.translator.inference.SpeechPlayer
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/** Real platform codec tests using generated non-sensitive local PCM, no model inference. */
@RunWith(AndroidJUnit4::class)
class AudioImportTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    @Test fun decodesAndResamplesAcrossCodecPacketBoundaries() {
        for(rate in listOf(8000,16000,48000)) {
            val file=File.createTempFile("import-fixture-",".wav",context.cacheDir)
            try {
                val source=FloatArray(rate/2) { (.5*sin(2*PI*440*it/rate)).toFloat() }
                SpeechPlayer.writeWav(file,SpeechAudio(source,rate))
                val result=AudioImport.decode(context,Uri.fromFile(file)) { false }
                assertEquals("Half a second at 16 kHz",8000,result.size)
                assertTrue(result.all { it.isFinite() })
                // A known waveform oracle checks packet continuity and conversion, not just length.
                val error=(32 until result.size-32).maxOf { abs(result[it]-(.5*sin(2*PI*440*it/16000)).toFloat()) }
                assertTrue("Rate $rate: max waveform error $error",error<.035f)
            } finally { file.delete() }
        }
    }
    @Test fun downmixesStereoWithoutDroppingAChannel() {
        val file=File.createTempFile("stereo-fixture-",".wav",context.cacheDir)
        try {
            val frames=8000
            file.outputStream().use { out ->
                fun word(v:Int) { out.write(v and 255);out.write((v ushr 8) and 255) }
                fun int(v:Int) { word(v and 65535);word(v ushr 16) }
                fun str(v:String) { out.write(v.toByteArray(Charsets.US_ASCII)) }
                str("RIFF");int(36+frames*4);str("WAVEfmt ");int(16);word(1);word(2);int(16000);int(64000);word(4);word(16);str("data");int(frames*4)
                repeat(frames) { i -> val sample=(12000*sin(2*PI*330*i/16000)).toInt();word(sample);word(-sample) }
            }
            val result=AudioImport.decode(context,Uri.fromFile(file)) { false }
            assertEquals(frames,result.size)
            assertTrue("Opposite stereo channels should cancel",result.all { abs(it)<.0001f })
        } finally { file.delete() }
    }
    @Test fun cancellationRemovesPrivatePcmSpool() {
        val file=File.createTempFile("cancel-fixture-",".wav",context.cacheDir)
        val before=context.cacheDir.listFiles().orEmpty().filter { it.name.startsWith("audio-import-") }.map { it.name }.toSet()
        try {
            SpeechPlayer.writeWav(file,SpeechAudio(FloatArray(1600){.2f},16000))
            try { AudioImport.decode(context,Uri.fromFile(file)) { true };fail("Expected cancellation") }
            catch(expected:IllegalStateException) { assertEquals("Cancelled",expected.message) }
            val after=context.cacheDir.listFiles().orEmpty().filter { it.name.startsWith("audio-import-") }.map { it.name }.toSet()
            assertEquals(before,after)
        } finally { file.delete() }
    }
}
