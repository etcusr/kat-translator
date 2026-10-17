package org.openoffline.translator.inference

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual AudioTrack lifecycle, drain accounting and bounded recording normalization. */
@RunWith(AndroidJUnit4::class)
class SpeechPlaybackTest {
    private fun player()=SpeechPlayer(InstrumentationRegistry.getInstrumentation().targetContext)
    @Test fun recordingReplayNormalizesWithoutChangingSourceAndDrainsOnce() {
        val source=FloatArray(16000) { i -> (.005*kotlin.math.sin(i*.17)).toFloat() }
        val original=source.copyOf()
        val expected=SpeechLoudness.recordingGain(source,16000) ?: 1.0
        player().use { p ->
            p.play(SpeechAudio(source,16000),normalizeVolume=true)
            val deadline=SystemClock.elapsedRealtime()+5000
            while(p.isPlaying && SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(20)
            val metrics=requireNotNull(p.metrics)
            assertNull(metrics.failure);assertTrue(metrics.completed)
            assertEquals(16000L,metrics.written);assertEquals(metrics.written,metrics.played)
            assertEquals(expected,p.appliedGain,1e-9);assertArrayEquals(original,source,0f)
        }
    }
    @Test fun changingSpeedPreservesPlaybackAndPause() {
        player().use { p ->
            p.play(SpeechAudio(FloatArray(16000*10),16000))
            assertTrue(p.isPlaying)
            p.setSpeed(1.5f)
            SystemClock.sleep(80)
            assertTrue("Speed change must not stop current audio",p.isPlaying)
            p.pause()
            assertTrue(p.isPaused)
            p.setSpeed(.75f)
            SystemClock.sleep(80)
            assertTrue("Speed change must not resume paused audio",p.isPaused)
            p.resume()
            assertFalse(p.isPaused)
            assertTrue(p.isPlaying)
        }
    }
    @Test fun stopThenStartDoesNotInheritOldWorkerState() {
        player().use { p ->
            repeat(3) {
                p.play(SpeechAudio(FloatArray(16000),16000))
                p.pause()
                p.stop()
                assertFalse(p.isPlaying)
                assertFalse(p.isPaused)
            }
            p.play(SpeechAudio(FloatArray(16000),16000))
            assertTrue(p.isPlaying)
            assertFalse(p.isPaused)
        }
    }
    @Test fun streamingDrainsEveryFrameOnceAndIgnoresLateStoppedProducer() {
        player().use { p ->
            val first=p.startStream(16000,1.25f)
            first.offer(FloatArray(16000));SystemClock.sleep(100)
            p.pause();assertTrue(p.isPaused);p.setSpeed(2f);assertTrue(p.isPaused)
            first.offer(FloatArray(8000));first.finish();p.resume()
            val deadline=SystemClock.elapsedRealtime()+10_000
            while(p.isPlaying && SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(20)
            val metrics=requireNotNull(p.metrics)
            assertNull(metrics.failure);assertTrue(metrics.completed)
            assertEquals(24000L,metrics.written);assertEquals(metrics.written,metrics.played)
            val stopped=p.startStream(16000);stopped.offer(FloatArray(16000));p.stop()
            assertFalse(stopped.offer(FloatArray(16000)));assertFalse(p.isPlaying)
            val current=p.startStream(16000);current.offer(FloatArray(8000));current.finish()
            stopped.finish();assertTrue(p.isPlaying)
        }
    }
    @Test fun veryShortStreamCompletesAndPauseMayRaceNaturalCompletion() {
        player().use { p ->
            p.startStream(16000,2f).apply { offer(FloatArray(128));finish() }
            val deadline=SystemClock.elapsedRealtime()+5000
            while(p.isPlaying && SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(10)
            assertTrue(requireNotNull(p.metrics).completed)
            repeat(20) { p.pause();p.resume();p.setSpeed(1.25f) }
            assertFalse(p.isPlaying)
        }
    }
}
