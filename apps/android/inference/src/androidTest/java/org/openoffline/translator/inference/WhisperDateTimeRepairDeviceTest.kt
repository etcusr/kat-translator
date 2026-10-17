package org.openoffline.translator.inference

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Opt-in synthetic PCM only. Supply app-readable modelPath and fixtureRoot containing
 * time-first.f32 and money.f32 (16 kHz mono little-endian float PCM). */
class WhisperDateTimeRepairDeviceTest {
    private val args get() = InstrumentationRegistry.getArguments()
    private fun pcm(name:String):FloatArray {
        val bytes=File(requireNotNull(args.getString("fixtureRoot")),"$name.f32").readBytes()
        require(bytes.isNotEmpty() && bytes.size%4==0)
        return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().let { buffer -> FloatArray(buffer.remaining()).also { buffer.get(it) } }
    }
    @Test fun baseline()=exercise(WhisperBackend.BASELINE)
    @Test fun arm82() { assumeTrue(MediaNative.acceleratedWhisper);exercise(WhisperBackend.ARM82) }
    @Test fun i8mm() { assumeTrue(MediaNative.i8mmWhisper);exercise(WhisperBackend.I8MM) }
    private fun exercise(backend:WhisperBackend) {
        assumeTrue(args.getString("whisperDateTimeRepair")=="true")
        val path=requireNotNull(args.getString("modelPath")).toByteArray()
        val ambiguous=pcm("time-first");val ordinary=pcm("money")
        val handle=when(backend) {
            WhisperBackend.BASELINE -> MediaNative.whisperCreate(path)
            WhisperBackend.ARM82 -> MediaNative.whisperArm82Create(path)
            WhisperBackend.I8MM -> MediaNative.whisperI8mmCreate(path)
        }
        assertTrue(handle!=0L)
        var flag=MediaNative.flagCreate()
        var retries=0
        var passes=0
        fun decode(samples:FloatArray,words:Boolean=false):String? {
            val language="ru".toByteArray()
            val start=SystemClock.elapsedRealtimeNanos()
            val raw=when(backend) {
                WhisperBackend.BASELINE -> if(words)MediaNative.whisperWordsRun(handle,samples,language,flag) else MediaNative.whisperRun(handle,samples,language,flag)
                WhisperBackend.ARM82 -> if(words)MediaNative.whisperArm82WordsRun(handle,samples,language,flag) else MediaNative.whisperArm82Run(handle,samples,language,flag)
                WhisperBackend.I8MM -> if(words)MediaNative.whisperI8mmWordsRun(handle,samples,language,flag) else MediaNative.whisperI8mmRun(handle,samples,language,flag)
            }
            val seconds=(SystemClock.elapsedRealtimeNanos()-start)/1e9
            InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply {
                putString("stream","\nWHISPER_PASS backend=$backend pass=${++passes} words=$words samples=${samples.size} seconds=$seconds cancelled=${raw==null}\n")
            })
            if(raw==null)return null
            val output=String(raw,Charsets.UTF_8)
            check(output.startsWith("ru\n"))
            return output.substringAfter('\n').trim()
        }
        try {
            val baseline=requireNotNull(decode(ambiguous))
            assertTrue("Unexpected synthetic baseline: $baseline",baseline in setOf("Поезд прибудет 22.18.16 октября.","Поезд прибудет 22-18-16 октября."))
            val off=WhisperDateTimeRepair.apply(baseline,"ru",ambiguous.size) { retries++;requireNotNull(decode(ambiguous,true)) }
            assertEquals(baseline,off);assertEquals(0,retries)
            repeat(2) {
                val result=WhisperDateTimeRepair.apply(requireNotNull(decode(ambiguous)),"ru",ambiguous.size,true) { retries++;requireNotNull(decode(ambiguous,true)) }
                assertEquals("Поезд прибудет 22:18, 16 октября.",result)
            }
            assertEquals(2,retries)
            val ordinaryText=requireNotNull(decode(ordinary))
            assertEquals(ordinaryText,WhisperDateTimeRepair.apply(ordinaryText,"ru",ordinary.size,true) { error("Ordinary numbers must not retry") })
            // Both entry points must respect cancellation and leave the cached context reusable.
            MediaNative.flagCancel(flag)
            assertNull(decode(ambiguous));assertNull(decode(ambiguous,true))
            MediaNative.flagFree(flag);flag=MediaNative.flagCreate()
            assertEquals(baseline,decode(ambiguous))
            assertEquals(ordinaryText,decode(ordinary))
        } finally {
            MediaNative.flagFree(flag)
            when(backend) {
                WhisperBackend.BASELINE -> MediaNative.whisperFree(handle)
                WhisperBackend.ARM82 -> MediaNative.whisperArm82Free(handle)
                WhisperBackend.I8MM -> MediaNative.whisperI8mmFree(handle)
            }
        }
    }
}
