package org.openoffline.translator.android

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.abs

/** The production decoder must feed the same recording as the accepted native ASR test. */
@RunWith(AndroidJUnit4::class)
class RealAudioImportTest {
    @Test fun fixtureMatchesReferencePcmWithoutDurationOrAmplitudeChange() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val data=inst.context.assets.open("media-asr-en.fixture").use { it.readBytes() }
        fun word(i:Int)=(data[i].toInt() and 255) or ((data[i+1].toInt() and 255) shl 8)
        fun number(i:Int)=word(i) or (word(i+2) shl 16)
        assertEquals(1,word(20));assertEquals(1,word(22));assertEquals(16,word(34))
        val rate=number(24)
        val pcm=FloatArray((data.size-44)/2) { word(44+it*2).toShort()/32768f }
        val fixture=File.createTempFile("asr-reference-",".wav",inst.targetContext.cacheDir)
        try {
            fixture.writeBytes(data)
            val actual=AudioImport.decode(inst.targetContext,Uri.fromFile(fixture)) { false }
            val count=(pcm.size.toLong()*16000/rate).toInt()
            assertTrue("Duration must not expand or truncate",abs(count-actual.size)<=1)
            var maxError=0f
            for(i in 0 until minOf(count,actual.size)) {
                val position=i.toDouble()*rate/16000
                val a=position.toInt().coerceAtMost(pcm.lastIndex);val b=(a+1).coerceAtMost(pcm.lastIndex)
                val expected=(pcm[a]*(1-(position-a))+pcm[b]*(position-a)).toFloat()
                maxError=maxOf(maxError,abs(expected-actual[i]))
            }
            assertTrue("PCM changed beyond one 16-bit rounding step: $maxError",maxError<=2f/32768)
        } finally { fixture.delete() }
    }
}
