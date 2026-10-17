package org.openoffline.translator.inference
import org.junit.Assert.*
import org.junit.Test
class SpeechStreamTest {
    @Test fun orderedDrainNeverReplaysAndRejectsLateFragments() {
        val q=SpeechStream();q.offer(floatArrayOf(1f,2f));q.offer(floatArrayOf(3f));q.finish()
        assertArrayEquals(floatArrayOf(1f,2f),q.take(),0f);assertArrayEquals(floatArrayOf(3f),q.take(),0f)
        assertNull(q.take());assertNull(q.take());assertFalse(q.offer(floatArrayOf(4f)))
    }
    @Test fun stopDropsQueuedAndWakesConsumer() {
        val q=SpeechStream();q.offer(floatArrayOf(1f));q.stop()
        assertFalse(q.offer(floatArrayOf(2f)));assertNull(q.take())
        val waiting=SpeechStream();val t=Thread { assertNull(waiting.take()) };t.start();waiting.stop();t.join(1000);assertFalse(t.isAlive)
    }
    @Test fun fixedLoudnessDoesNotJumpAtSentenceBoundary() {
        val n=StreamingSpeechLoudness()
        val first=requireNotNull(n.accept(SpeechAudio(FloatArray(16000) { .04f },16000)))
        val second=requireNotNull(n.accept(SpeechAudio(FloatArray(800) { .08f },16000)))
        assertEquals(16000,first.samples.size);assertEquals(800,second.samples.size)
        assertEquals(2f,second.samples[0]/first.samples[0],.00001f)
        assertTrue(second.samples.all { it.isFinite() && kotlin.math.abs(it)<=.89f })
    }
    @Test fun shortOpeningWaitsForRepresentativeGainAndFlushesOnce() {
        val n=StreamingSpeechLoudness()
        assertNull(n.accept(SpeechAudio(FloatArray(800) { .01f },16000)))
        val combined=requireNotNull(n.accept(SpeechAudio(FloatArray(16000) { .1f },16000)))
        assertEquals(16800,combined.samples.size);assertNull(n.finish())
        val short=StreamingSpeechLoudness()
        assertNull(short.accept(SpeechAudio(FloatArray(128) { .1f },16000)))
        assertEquals(128,requireNotNull(short.finish()).samples.size);assertNull(short.finish())
    }
    @Test fun openingBufferDeliversEveryChunkOnceAndFlushesShortUtterance() {
        val b=SpeechStartBuffer();val a=SpeechAudio(FloatArray(16000),16000)
        repeat(3) { assertTrue(b.accept(a).isEmpty()) }
        assertEquals(4,b.accept(a).size);assertEquals(1,b.accept(a).size)
        assertTrue(b.finish().isEmpty())
        val short=SpeechStartBuffer();assertTrue(short.accept(a).isEmpty())
        assertEquals(listOf(a),short.finish());assertTrue(short.finish().isEmpty())
    }
}
