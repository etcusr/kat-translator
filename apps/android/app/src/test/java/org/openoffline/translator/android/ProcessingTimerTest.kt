package org.openoffline.translator.android
import org.junit.Assert.*
import org.junit.Test
class ProcessingTimerTest {
    @Test fun sumsAllCameraBlocksAndIncludesPreparationOnlyInTotal() {
        var now=0L
        val timer=ProcessingTimer(clock={now})
        timer.add(ProcessingStage.RECOGNITION,.4)
        timer.add(ProcessingStage.TRANSLATION,.2);timer.add(ProcessingStage.TRANSLATION,.3)
        timer.add(ProcessingStage.MODEL_LOAD,2.0)
        now=3_000_000_000L
        assertEquals(.5,timer.snapshot().translation!!,1e-9)
        assertEquals(.4,timer.snapshot().recognition!!,1e-9)
        assertEquals(3.0,timer.snapshot().total,1e-9)
        assertNull(timer.snapshot().synthesis)
    }
    @Test fun manualSpeechAddsProcessingTimeWithoutCountingUserWaitOrPlayback() {
        val previous=ProcessingTiming(recognition=.5,translation=.3,total=1.0)
        var now=99_000_000_000L
        val timer=ProcessingTimer(previous) { now }
        timer.add(ProcessingStage.SYNTHESIS,.2);now+=300_000_000L
        val result=timer.snapshot()
        assertEquals(.2,result.synthesis!!,1e-9);assertEquals(1.3,result.total,1e-9)
        assertEquals(previous.recognition,result.recognition)
        assertNull(ProcessingTimer().snapshot().translation)
    }
}
