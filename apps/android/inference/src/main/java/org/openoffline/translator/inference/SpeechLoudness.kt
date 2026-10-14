package org.openoffline.translator.inference

import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.math.tanh

/** Same active-RMS gain and soft peak limit as shared OfflineCore.SpeechLoudness.
 * Call only on playback/export PCM; recognition must keep the original samples. */
object SpeechLoudness {
    fun gain(samples: FloatArray, sampleRate: Int, maximumGain:Double=4.0): Double? {
        if(sampleRate<=0 || samples.isEmpty() || samples.any { !it.isFinite() })return null
        val window=maxOf(1,sampleRate/50)
        var energy=0.0;var active=0
        var start=0
        while(start<samples.size) {
            val end=minOf(samples.size,start+window)
            var sum=0.0
            for(i in start until end)sum+=samples[i].toDouble()*samples[i].toDouble()
            if(sum/(end-start)>0.000025) { energy+=sum;active+=end-start }
            start=end
        }
        if(active==0 || energy<=0)return null
        return (0.16/sqrt(energy/active)).coerceIn(1.0,maximumGain)
    }
    /** Pixel VOICE_RECOGNITION capture can be far below TTS level. Keep one fixed gain
     * for the entire utterance, exclude silence, and retain the same soft peak limit.
     * Already normalized history does not pass the limiter again at unity gain. */
    fun recordingGain(samples:FloatArray,sampleRate:Int):Double? =
        gain(samples,sampleRate,32.0)?.takeIf { it>1.01 }
    fun normalizeRecording(audio:SpeechAudio):SpeechAudio {
        val gain=recordingGain(audio.samples,audio.sampleRate) ?: return audio
        return SpeechAudio(FloatArray(audio.samples.size) { adjusted(audio.samples[it],gain) },audio.sampleRate)
    }
    fun adjusted(sample: Float, gain: Double): Float {
        val value=sample*gain;val magnitude=abs(value)
        val limited=if(magnitude<=.75)magnitude else .75+.14*tanh((magnitude-.75)/.14)
        return (if(value<0)-minOf(.89,limited) else minOf(.89,limited)).toFloat()
    }
    fun normalize(audio: SpeechAudio): SpeechAudio {
        val gain=gain(audio.samples,audio.sampleRate)?:return audio
        return SpeechAudio(FloatArray(audio.samples.size) { adjusted(audio.samples[it],gain) },audio.sampleRate)
    }
}
