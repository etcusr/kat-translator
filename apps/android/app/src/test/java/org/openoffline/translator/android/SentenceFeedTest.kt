package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test

class SentenceFeedTest {
    @Test fun finishedSentencesConcatenateToFinalText() {
        val feed = SentenceFeed()
        val final = "Today the weather is nice. We will walk in the park, then eat. Tomorrow — the museum."
        for (end in 1..final.length) feed.offer(final.substring(0, end))
        feed.finish(final)
        val pieces = feed.sentences().toList()
        assertEquals(listOf("Today the weather is nice.", "We will walk in the park, then eat.", "Tomorrow — the museum."), pieces)
        assertEquals(final, pieces.joinToString(" "))
    }
    @Test fun decimalsAndShortPiecesWait() {
        val feed = SentenceFeed()
        feed.offer("Version 3.5 is out"); feed.offer("Ok. ")
        feed.finish("Version 3.5 is out")
        assertEquals(listOf("Version 3.5 is out"), feed.sentences().toList())
        assertEquals(-1, SentenceFeed.lastBoundary("Price 3.5", 0))
        assertEquals(13, SentenceFeed.lastBoundary("He said «да.» Then", 0))
        assertEquals(2, SentenceFeed.lastBoundary("好。再见", 0))
    }
    @Test fun abortEndsWithoutRemainder() {
        val feed = SentenceFeed(); feed.offer("First finished sentence. Second"); feed.abort(); feed.finish("ignored")
        assertTrue(feed.sentences().toList().isEmpty())
    }
}
