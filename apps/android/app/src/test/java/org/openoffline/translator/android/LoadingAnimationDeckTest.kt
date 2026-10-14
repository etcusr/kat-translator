package org.openoffline.translator.android
import org.junit.Assert.*
import org.junit.Test
class LoadingAnimationDeckTest {
    @Test fun everyClipAppearsBeforeRepeatingIncludingAcrossWaits() {
        val clips=listOf("a","b","c");val deck=LoadingAnimationDeck(clips) { it }
        repeat(10) { assertEquals(clips.toSet(),List(3) { deck.next() }.toSet()) }
    }
    @Test fun roundBoundaryCannotRepeatPreviousClip() {
        var round=0
        val deck=LoadingAnimationDeck(listOf("a","b","c")) { if(round++%2==0)it else it.reversed() }
        val played=List(30) { deck.next() }
        assertTrue(played.zipWithNext().all { (a,b)->a!=b })
    }
    @Test fun emptyAndSingleClipFallbackAreSafe() {
        assertNull(LoadingAnimationDeck(emptyList()).next())
        val deck=LoadingAnimationDeck(listOf("one"));repeat(4) { assertEquals("one",deck.next()) }
    }
}
