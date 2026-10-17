package org.openoffline.translator.inference

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/** A single utterance. Closing input drains it; stopping drops it and rejects late producers. */
class SpeechStream {
    private val queue=LinkedBlockingQueue<FloatArray>()
    private val end=FloatArray(0)
    private var closed=false
    val stopped=AtomicBoolean(false)
    @Synchronized fun offer(samples:FloatArray):Boolean {
        if(closed || stopped.get())return false
        require(samples.isNotEmpty() && samples.all { it.isFinite() })
        return offerValidated(samples)
    }
    /** SpeechAudio already validated this PCM; avoid scanning a long recording on the UI thread. */
    @Synchronized internal fun offerValidated(samples:FloatArray):Boolean {
        if(closed || stopped.get())return false
        queue.add(samples);return true
    }
    @Synchronized fun finish() { if(!closed) { closed=true;queue.add(end) } }
    @Synchronized fun stop() { stopped.set(true);closed=true;queue.clear();queue.add(end) }
    fun take():FloatArray? {
        if(stopped.get())return null
        val next=queue.take()
        if(next===end) { queue.offer(end);return null }
        return next.takeUnless { stopped.get() }
    }
}

/** Estimate one gain from at least 0.8 s, or the whole utterance if shorter.
 * Keep that gain and the existing soft limiter for every subsequent chunk and for replay/export. */
class StreamingSpeechLoudness {
    private var gain:Double?=null
    private var sampleRate=0
    private var ready=false
    private var finished=false
    private val pending=mutableListOf<FloatArray>()
    private var count=0
    fun accept(audio:SpeechAudio):SpeechAudio? {
        check(!finished)
        if(sampleRate==0)sampleRate=audio.sampleRate
        require(sampleRate==audio.sampleRate)
        if(ready)return normalize(audio.samples)
        pending+=audio.samples;count+=audio.samples.size
        return if(count>=sampleRate*4/5)flush() else null
    }
    fun finish():SpeechAudio? { if(finished)return null;finished=true;return if(count>0)flush() else null }
    private fun flush():SpeechAudio {
        val samples=FloatArray(count);var offset=0
        pending.forEach { it.copyInto(samples,offset);offset+=it.size }
        pending.clear();count=0
        gain=SpeechLoudness.gain(samples,sampleRate);ready=true
        return normalize(samples)
    }
    private fun normalize(samples:FloatArray):SpeechAudio {
        val value=gain ?: return SpeechAudio(samples,sampleRate)
        return SpeechAudio(FloatArray(samples.size) { SpeechLoudness.adjusted(samples[it],value) },sampleRate)
    }
}

/** Tiny opening sentences must not outrun synthesis of the next sentence. No audio is discarded. */
class SpeechStartBuffer(private val seconds:Int=4) {
    private val pending=mutableListOf<SpeechAudio>()
    private var samples=0
    private var started=false
    fun accept(audio:SpeechAudio):List<SpeechAudio> {
        if(started)return listOf(audio)
        pending+=audio;samples+=audio.samples.size
        return if(samples>=audio.sampleRate*seconds)flush() else emptyList()
    }
    fun finish():List<SpeechAudio> = flush()
    private fun flush():List<SpeechAudio> {
        started=true
        return pending.toList().also { pending.clear();samples=0 }
    }
}
