package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test

class WhisperModelCacheTest {
    private val q8 = "ggml-large-v3-turbo-q8_0.bin"

    @Test fun i8mmOnlyForVerifiedQ8WithBothLibrariesAvailable() {
        assertEquals(WhisperBackend.I8MM, whisperBackendFor(q8, arm82Available = true, i8mmAvailable = true))
        assertEquals(WhisperBackend.ARM82, whisperBackendFor(q8, arm82Available = true, i8mmAvailable = false))
        assertEquals(WhisperBackend.BASELINE, whisperBackendFor(q8, arm82Available = false, i8mmAvailable = true))
        assertEquals(WhisperBackend.BASELINE, whisperBackendFor(q8, arm82Available = false, i8mmAvailable = false))
    }

    @Test fun otherModelsNeverUseI8mm() {
        for (name in listOf("ggml-large-v3-turbo.bin", "ggml-large-v3-turbo-q8_0.bin.part", "ggml-large-v3-turbo-q5_0.bin",
                            "GGML-LARGE-V3-TURBO-Q8_0.BIN", "x/ggml-large-v3-turbo-q8_0.bin", "")) {
            assertEquals(name, WhisperBackend.ARM82, whisperBackendFor(name, arm82Available = true, i8mmAvailable = true))
            assertEquals(name, WhisperBackend.BASELINE, whisperBackendFor(name, arm82Available = false, i8mmAvailable = true))
        }
    }

    @Test fun reusesSameIdentityAndBackend() {
        val freed = mutableListOf<Pair<WhisperBackend, Long>>(); var created = 0L
        val cache = WhisperModelCache { b, h -> freed += b to h }
        assertEquals(1L, cache.acquire("model", WhisperBackend.ARM82) { ++created })
        assertEquals(1L, cache.acquire("model", WhisperBackend.ARM82) { fail("must reuse"); 0L })
        assertEquals(1, cache.loads); assertEquals(WhisperBackend.ARM82, cache.backend)
        assertTrue(freed.isEmpty())
    }

    @Test fun backendSwitchWithSameIdentityFreesOldOwnerBeforeCreate() {
        val events = mutableListOf<String>(); var created = 10L
        val cache = WhisperModelCache { b, h -> events += "free $b $h" }
        cache.acquire("model", WhisperBackend.ARM82) { b -> events += "create $b"; ++created }
        val handle = cache.acquire("model", WhisperBackend.I8MM) { b -> events += "create $b"; ++created }
        assertEquals(12L, handle)
        assertEquals(listOf("create ARM82", "free ARM82 11", "create I8MM"), events)
        assertEquals(WhisperBackend.I8MM, cache.backend); assertEquals(2, cache.loads)
    }

    @Test fun identityChangeFreesWithItsOwnBackend() {
        val freed = mutableListOf<Pair<WhisperBackend, Long>>()
        val cache = WhisperModelCache { b, h -> freed += b to h }
        cache.acquire("a", WhisperBackend.I8MM) { 5L }
        cache.acquire("b", WhisperBackend.ARM82) { assertEquals(listOf(WhisperBackend.I8MM to 5L), freed); 6L }
        assertEquals(listOf(WhisperBackend.I8MM to 5L), freed)
    }

    @Test fun createReceivesRequestedBackend() {
        val cache = WhisperModelCache { _, _ -> }
        var seen: WhisperBackend? = null
        cache.acquire("a", WhisperBackend.BASELINE) { seen = it; 1L }
        assertEquals(WhisperBackend.BASELINE, seen)
    }

    @Test fun failedLoadIsNotCachedAndCanBeRetried() {
        val freed = mutableListOf<Long>()
        val cache = WhisperModelCache { _, h -> freed += h }
        cache.acquire("a", WhisperBackend.ARM82) { 1L }
        assertThrows(IllegalStateException::class.java) { cache.acquire("b", WhisperBackend.ARM82) { 0L } }
        assertEquals(listOf(1L), freed)          // the previous model was released before the failed load
        assertNull(cache.backend); assertEquals(1, cache.loads)
        assertThrows(RuntimeException::class.java) { cache.acquire("b", WhisperBackend.I8MM) { throw RuntimeException("load") } }
        assertNull(cache.backend)
        assertEquals(2L, cache.acquire("b", WhisperBackend.I8MM) { 2L })
        assertEquals(2, cache.loads); assertEquals(listOf(1L), freed)
    }

    @Test fun closeIsIdempotentAndUsesOwner() {
        val freed = mutableListOf<Pair<WhisperBackend, Long>>()
        val cache = WhisperModelCache { b, h -> freed += b to h }
        cache.acquire("a", WhisperBackend.I8MM) { 7L }
        cache.close(); cache.close()
        assertEquals(listOf(WhisperBackend.I8MM to 7L), freed)
        assertNull(cache.backend)
        assertEquals(8L, cache.acquire("a", WhisperBackend.I8MM) { 8L })   // reload after close
        assertEquals(2, cache.loads)
    }

    @Test fun closeWithoutModelDoesNothing() {
        var calls = 0
        WhisperModelCache { _, _ -> calls++ }.apply { close(); close() }
        assertEquals(0, calls)
    }
}
