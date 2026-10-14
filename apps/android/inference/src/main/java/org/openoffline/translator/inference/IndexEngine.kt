package org.openoffline.translator.inference

internal object NativeBridge {
    init { System.loadLibrary("kat_index") }
    external fun load(path: ByteArray, threads: Int, gpu: Boolean, flash: Boolean, mtp: Boolean): Long
    external fun gpuName(): String
    external fun readBandwidth(threads: Int, megabytes: Int, seconds: Double): Double
    external fun gpuMatvecBandwidth(seconds: Double): Double
    external fun free(handle: Long)
    external fun flagCreate(): Long
    external fun flagCancel(flag: Long)
    external fun flagFree(flag: Long)
    external fun tokens(handle: Long, prefix: ByteArray, text: ByteArray, suffix: ByteArray): IntArray
    external fun run(handle: Long, prefix: ByteArray, text: ByteArray, suffix: ByteArray, flag: Long, outputBytes: Int, stats: DoubleArray): ByteArray
    external fun echo(text: ByteArray): ByteArray
}
sealed class TranslationResult {
    data class Success(val text: String, val firstTokenSeconds: Double, val draftedTokens: Int=0, val acceptedTokens: Int=0): TranslationResult()
    data object Limit: TranslationResult()
    data object Cancelled: TranslationResult()
    data class Failure(val code: Int): TranslationResult()
}
/** One worker owns inference. close waits; cancellation can run concurrently. */
class IndexEngine private constructor(private var handle: Long, val mtpEnabled: Boolean): AutoCloseable {
    private val flagLock=Any()
    private var activeFlag=0L
    @Synchronized fun sourceTokenCount(text: String): Int {
        check(handle!=0L) { "Engine closed" }
        return NativeBridge.tokens(handle,byteArrayOf(),IndexRequest.utf8(text),byteArrayOf()).size
    }
    @Synchronized fun tokens(request: IndexRequest): IntArray {
        check(handle!=0L) { "Engine closed" }
        return NativeBridge.tokens(handle,IndexRequest.utf8(request.prefix),IndexRequest.utf8(request.text),IndexRequest.utf8(request.suffix))
    }
    @Synchronized fun translate(request: IndexRequest, enforceReserve: Boolean=true, outputBytes: Int=65536): TranslationResult {
        check(handle!=0L) { "Engine closed" }
        require(outputBytes in 1..65536)
        val prefix=IndexRequest.utf8(request.prefix);val text=IndexRequest.utf8(request.text);val suffix=IndexRequest.utf8(request.suffix)
        val count=NativeBridge.tokens(handle,prefix,text,suffix).size
        val source=NativeBridge.tokens(handle,byteArrayOf(),text,byteArrayOf()).size
        if (enforceReserve && !IndexRequest.fits(count,source)) return TranslationResult.Limit
        val flag=synchronized(flagLock) { NativeBridge.flagCreate().also { check(it!=0L);activeFlag=it } }
        try {
            val stats=DoubleArray(4)
            val output=NativeBridge.run(handle,prefix,text,suffix,flag,outputBytes,stats)
            return when(stats[0].toInt()) {
                0->TranslationResult.Success(String(output,Charsets.UTF_8),stats[1],stats[2].toInt(),stats[3].toInt())
                1->TranslationResult.Limit
                2->TranslationResult.Cancelled
                else->TranslationResult.Failure(stats[0].toInt())
            }
        } finally { synchronized(flagLock) { activeFlag=0L;NativeBridge.flagFree(flag) } }
    }
    fun cancel(): Boolean = synchronized(flagLock) { if(activeFlag==0L) false else { NativeBridge.flagCancel(activeFlag); true } }
    @Synchronized override fun close() { if(handle!=0L) { NativeBridge.free(handle);handle=0L } }
    companion object {
        fun gpuName(): String = NativeBridge.gpuName()
        /** Sustained multi-thread memory read bandwidth, GB/s (about one second, 128 MB). */
        fun readBandwidthGbps(seconds: Double = 1.5): Double = NativeBridge.readBandwidth(4, 32, seconds)
        /** Q4_K matrix-vector throughput on the Vulkan device (same kernels as decoding), GB/s; -1 without GPU. */
        fun gpuMatvecGbps(seconds: Double = 2.0): Double = NativeBridge.gpuMatvecBandwidth(seconds)
        fun open(path: String, threads: Int=4, gpu: Boolean=true, flash: Boolean=true, mtp: Boolean=gpu): IndexEngine {
            require(threads in 1..8)
            require(!mtp || gpu) { "MTP requires the GPU backend" }
            val handle=NativeBridge.load(IndexRequest.utf8(path),threads,gpu,flash,mtp)
            check(handle!=0L) { "Index model could not be loaded" }
            return IndexEngine(handle,mtp)
        }
    }
}
