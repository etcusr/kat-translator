package org.openoffline.translator.inference

internal object OpusNative {
    init { System.loadLibrary("kat_opus") }
    external fun load(path: ByteArray): Long
    external fun prepare(handle: Long, direction: ByteArray, flag: Long): Int
    external fun free(handle: Long)
    external fun flagCreate(): Long
    external fun flagCancel(flag: Long)
    external fun flagFree(flag: Long)
    external fun count(handle: Long, text: ByteArray, direction: ByteArray, marker: ByteArray): Int
    external fun run(handle: Long, text: ByteArray, direction: ByteArray, marker: ByteArray, flag: Long, status: IntArray): ByteArray
}

/** One OPUS-MT model directory inside a package plus the target label it needs ("" if single-target). */
data class OpusRoute(val direction: String, val marker: String)

/** Identical shared OPUS C ABI/tokenizers/decoding limits; a serialized CPU alternative to Index.
 * The package catalog chooses the route; the engine only runs directions present in its package. */
class OpusEngine private constructor(private var handle: Long, val packageId: String) : AutoCloseable {
    private val flagLock = Any()
    private var activeFlag = 0L

    @Synchronized fun tokens(text: String, route: OpusRoute): Int {
        check(handle != 0L) { "OPUS is closed" }
        return OpusNative.count(handle, IndexRequest.utf8(text), IndexRequest.utf8(route.direction), IndexRequest.utf8(route.marker))
    }

    @Synchronized fun translate(text: String, route: OpusRoute): TranslationResult {
        check(handle != 0L) { "OPUS is closed" }
        val input = IndexRequest.utf8(text)
        if (tokens(text, route) > MAX_INPUT_TOKENS) return TranslationResult.Limit
        val flag = synchronized(flagLock) {
            OpusNative.flagCreate().also { check(it != 0L) { "Cannot create cancellation flag" }; activeFlag = it }
        }
        try {
            val status = IntArray(1)
            val result = OpusNative.run(handle, input, IndexRequest.utf8(route.direction), IndexRequest.utf8(route.marker), flag, status)
            return when (status[0]) {
                0 -> TranslationResult.Success(String(result, Charsets.UTF_8), -1.0)
                1 -> TranslationResult.Limit
                2 -> TranslationResult.Cancelled
                else -> TranslationResult.Failure(status[0])
            }
        } finally { synchronized(flagLock) { activeFlag = 0L; OpusNative.flagFree(flag) } }
    }

    @Synchronized fun prepare(route: OpusRoute) {
        check(handle!=0L) { "OPUS is closed" }
        val flag=synchronized(flagLock) { OpusNative.flagCreate().also { check(it!=0L);activeFlag=it } }
        try {
            val result=OpusNative.prepare(handle,IndexRequest.utf8(route.direction),flag)
            check(result==0) { if(result==2)"Cancelled" else "OPUS preparation failed" }
        } finally { synchronized(flagLock) { activeFlag=0L;OpusNative.flagFree(flag) } }
    }

    fun cancel(): Boolean = synchronized(flagLock) {
        if (activeFlag == 0L) false else { OpusNative.flagCancel(activeFlag); true }
    }
    @Synchronized override fun close() { if (handle != 0L) { OpusNative.free(handle); handle = 0L } }

    companion object {
        const val PACKAGE_ID = "opus-mt-big-en-zle-int8"
        const val MAX_INPUT_TOKENS = 480
        fun open(packageDirectory: String, packageId: String = PACKAGE_ID): OpusEngine {
            val handle = OpusNative.load(IndexRequest.utf8(packageDirectory))
            check(handle != 0L) { "OPUS package could not be loaded" }
            return OpusEngine(handle, packageId)
        }
    }
}
