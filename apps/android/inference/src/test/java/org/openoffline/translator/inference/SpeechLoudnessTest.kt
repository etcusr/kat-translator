package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

class SpeechLoudnessTest {
    @Test fun quietSpeechUsesTheSameBoundedGainAsAppleWithoutMutatingRecognitionInput() {
        val raw=FloatArray(1600) { if(it%2==0).02f else -.02f }
        val original=raw.copyOf()
        val output=SpeechLoudness.normalize(SpeechAudio(raw,16000))
        assertEquals(4.0,SpeechLoudness.gain(raw,16000)!!,1e-6)
        assertEquals(.08f,output.samples[0],1e-6f)
        assertArrayEquals(original,raw,0f)
        assertNotSame(raw,output.samples)
    }
    @Test fun silenceDoesNotRaiseTheGainOfActiveSpeech() {
        val voice=FloatArray(320) { .08f }
        assertEquals(2.0,SpeechLoudness.gain(voice,16000)!!,1e-6)
        assertEquals(SpeechLoudness.gain(voice,16000),SpeechLoudness.gain(voice+FloatArray(3200),16000))
        assertNull(SpeechLoudness.gain(FloatArray(3200),16000))
        assertNull(SpeechLoudness.gain(FloatArray(320) { .001f },16000))
    }
    @Test fun loudPeaksAreSoftLimitedSymmetricallyAndInvalidInputIsNotAmplified() {
        assertTrue(abs(SpeechLoudness.adjusted(1f,4.0))<=.89f)
        assertEquals(-SpeechLoudness.adjusted(1f,4.0),SpeechLoudness.adjusted(-1f,4.0),0f)
        assertEquals(.5f,SpeechLoudness.adjusted(.5f,1.0),0f)
        assertEquals(1.0,SpeechLoudness.gain(FloatArray(320) { .5f },16000)!!,0f.toDouble())
        assertNull(SpeechLoudness.gain(floatArrayOf(Float.NaN),16000))
        assertNull(SpeechLoudness.gain(floatArrayOf(.1f),0))
    }
    @Test fun sharedQuietRecordingReachesSpeechTargetWithoutChangingOriginalOrDuration() {
        val samples=FloatArray(1600) { if(it%2==0).02f else -.02f };val original=samples.copyOf()
        val file=java.io.File.createTempFile("quiet-shared-recording", ".wav")
        try {
            SpeechPlayer.writeWav(file,SpeechAudio(samples,16000),normalizeVolume=true)
            val bytes=file.readBytes();assertEquals(44+samples.size*2,bytes.size)
            for(i in samples.indices) {
                val value=((bytes[44+i*2].toInt() and 255) or (bytes[45+i*2].toInt() shl 8)).toShort().toFloat()/32768
                assertEquals(original[i]*8,value,2f/32768)
                assertTrue(abs(value)<.89f)
            }
            assertArrayEquals(original,samples,0f)
        } finally { file.delete() }
    }

    @Test fun pixelCaptureAndLegacyQuietHistoryReachTheSameTargetAsSynthesizedSpeech() {
        for(level in listOf(.008f,.0314f,.08f,.16f)) {
            val raw=FloatArray(3200) { if(it%2==0)level else -level }
            val output=SpeechLoudness.normalizeRecording(SpeechAudio(raw,16000))
            assertEquals(.16f,kotlin.math.abs(output.samples[0]),1e-6f)
            assertEquals(level,kotlin.math.abs(raw[0]),0f)
            assertArrayEquals(output.samples,SpeechLoudness.normalizeRecording(output).samples,1e-6f)
        }
        assertNull(SpeechLoudness.recordingGain(FloatArray(3200),16000))
        assertNull(SpeechLoudness.recordingGain(FloatArray(3200) { .001f },16000))
        assertTrue(SpeechLoudness.recordingGain(FloatArray(320) { .006f },16000)!!<=32)
    }

}
