package org.openoffline.translator.inference
import org.junit.Test
import org.junit.Assert.*
class RecordedSpeechSegmentsTest {
    @Test fun pausesSplitButNoSampleIsSkipped() {
        val size=65*16000
        val activity=BooleanArray((size+511)/512) { i -> i*512 !in 20*16000..21*16000 && i*512 !in 42*16000..43*16000 }
        val parts=RecordedSpeechSegments.plan(size,activity)
        assertEquals(3,parts.size);assertEquals(0,parts.first().start);assertEquals(size,parts.last().end)
        parts.zipWithNext().forEach { (a,b) -> assertEquals(a.end,b.start);assertFalse(b.overlapsPrevious) }
    }
    @Test fun continuousSpeechIsBoundedAndOverlapsInsteadOfLosingWordAtCut() {
        val size=80*16000
        val parts=RecordedSpeechSegments.plan(size,BooleanArray((size+511)/512) { true })
        assertEquals(size,parts.last().end)
        assertTrue(parts.all { it.end-it.start<=30*16000 })
        parts.zipWithNext().forEach { (a,b) -> assertEquals(8000,a.end-b.start);assertTrue(b.overlapsPrevious) }
    }
    @Test fun leadingAndTrailingSilenceDoNotBecomeEmptySessions() {
        val size=10*16000
        val parts=RecordedSpeechSegments.plan(size,BooleanArray((size+511)/512) { i -> i*512 in 2*16000..6*16000 })
        assertEquals(listOf(RecordedSpeechSegments.Slice(0,size)),parts)
    }
    @Test fun forcedOverlapIsMergedButRepeatedUtterancesRemain() {
        assertEquals("Встреча завтра в Москве",RecordedSpeechSegments.append("Встреча завтра","Завтра в Москве",true))
        assertEquals("да да",RecordedSpeechSegments.append("да","да",false))
    }
}
