package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test

class TranslationRoutingTest {
    private class Resource(private val name: String, private val events: MutableList<String>) : AutoCloseable {
        override fun close() { events += name }
    }
    @Test fun switchingModelsReleasesThePreviousRuntimeAndLeaseBeforeLoading() {
        val events = mutableListOf<String>()
        val resources = TranslationResources<Resource, Resource>()
        resources.opus = Resource("close opus", events)
        resources.opusLease = Resource("close opus lease", events)
        resources.useIndex()
        assertEquals(listOf("close opus", "close opus lease"), events)
        assertNull(resources.opus); assertNull(resources.opusLease)
        resources.index = Resource("close index", events)
        resources.indexLease = Resource("close index lease", events)
        resources.useOpus()
        assertEquals(listOf("close opus", "close opus lease", "close index", "close index lease"), events)
        assertNull(resources.index); assertNull(resources.indexLease)
        resources.close()
        assertEquals(4, events.size)
    }
    @Test fun sameLanguagePassesThroughWithoutResolvingOrLoadingAnyModel() {
        assertEquals("Hello", TranslationRouting.translate("Hello", "en", "en") { error("Must not load a model") })
        assertEquals("Привет", TranslationRouting.translate("Hello", "en", "ru") { "Привет" })
    }
}
