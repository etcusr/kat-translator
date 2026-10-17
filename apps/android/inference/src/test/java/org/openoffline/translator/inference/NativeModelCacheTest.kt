package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test

class NativeModelCacheTest {
    @Test fun reusesExactlyOneModelAndReleasesBeforeReplacement() {
        val freed=mutableListOf<Long>();var created=0L
        val cache=NativeModelCache { freed+=it }
        assertEquals(1L,cache.acquire("a") { ++created })
        assertEquals(1L,cache.acquire("a") { ++created })
        assertEquals(2L,cache.acquire("changed metadata") { assertEquals(listOf(1L),freed);++created })
        cache.close();cache.close();assertEquals(listOf(1L,2L),freed)
        assertEquals(3L,cache.acquire("changed metadata") { ++created })
        cache.close()
    }
    @Test fun failedCreationDoesNotCacheAnInvalidHandle() {
        val cache=NativeModelCache { fail("Nothing to free") }
        try { cache.acquire("a") { 0 };fail("Must reject zero") } catch(_:IllegalStateException) {}
        assertEquals(7L,cache.acquire("a") { 7 })
    }
}
