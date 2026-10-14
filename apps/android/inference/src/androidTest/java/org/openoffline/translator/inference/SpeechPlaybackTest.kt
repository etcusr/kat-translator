package org.openoffline.translator.inference

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual AudioTrack lifecycle, with silence to avoid audible test tones. */
@RunWith(AndroidJUnit4::class)
class SpeechPlaybackTest {
    private fun player()=SpeechPlayer(InstrumentationRegistry.getInstrumentation().targetContext)
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
}
