package org.openoffline.translator.android

/** Serialized worker ownership: release the inactive native context before acquiring another. */
internal class TranslationResources<I : AutoCloseable, O : AutoCloseable> : AutoCloseable {
    @Volatile var index: I? = null
    var indexLease: AutoCloseable? = null
    @Volatile var opus: O? = null
    var opusLease: AutoCloseable? = null
    fun useIndex() { opus?.close(); opus = null; opusLease?.close(); opusLease = null }
    fun useOpus() { index?.close(); index = null; indexLease?.close(); indexLease = null }
    override fun close() { useIndex(); useOpus() }
}

internal object TranslationRouting {
    /** Detection can produce the target language; no model or route is needed in that case. */
    inline fun translate(text: String, source: String, target: String, inference: () -> String): String =
        if (source == target) text else inference()
}
