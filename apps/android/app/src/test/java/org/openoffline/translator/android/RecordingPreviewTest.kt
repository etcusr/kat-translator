package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test

class RecordingPreviewTest {
    private fun session()=RecordingPreview("ru","en",true,true)
    @Test fun silenceAndMinimumDurationMatchIosBoundary() {
        val s=session()
        assertNull(s.next(32000,24000))
        assertNull(s.next(16000,1))
        assertEquals(0 until 40000,s.next(40000,24000))
        assertNull(s.next(80000,60000)) // Never queue another native request.
    }
    @Test fun onlyCompletedSentenceAdvancesAndNextChunkDoesNotOverlap() {
        val s=session();val a=s.next(48000,32000)!!
        assertFalse(s.commit(a,"unfinished","translation","ru"))
        assertEquals(0,s.prepared().end)
        val b=s.next(96000,80000)!!
        assertEquals(0,b.first)
        assertTrue(s.commit(b,"First sentence.","Первое предложение.","en"))
        assertEquals(96000 until 144000,s.next(144000,128000))
        assertEquals("First sentence.",s.prepared().sourceText)
    }
    @Test fun cancellationRejectsStaleResultAndLongSnapshotFallsBack() {
        val s=session();val range=s.next(48000,32000)!!;s.cancel()
        assertFalse(s.commit(range,"Hello.","Привет.","en"))
        assertTrue(s.prepared().blocks.isEmpty())
        val large=session();assertNull(large.next(500000,480000));assertTrue(large.suspended)
    }
    @Test fun pauseOrBackgroundPreservesCommittedTextWithoutAcceptingLaterWork() {
        val s=session();assertTrue(s.commit(s.next(48000,32000)!!,"Привет!","Hello!","ru"))
        val next=s.next(96000,80000)!!;s.suspend()
        assertFalse(s.commit(next,"Нет.","No.","ru"))
        assertEquals("Hello!",s.prepared().translation)
    }
}
