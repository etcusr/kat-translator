package org.openoffline.translator.android

/** Measured processing only: total includes preparation/I/O, but never recording or playback. */
data class ProcessingTiming(
    val recognition:Double?=null, val translation:Double?=null, val synthesis:Double?=null,
    val modelLoad:Double?=null, val total:Double=0.0,
)
internal enum class ProcessingStage { RECOGNITION, TRANSLATION, SYNTHESIS, MODEL_LOAD }
internal class ProcessingTimer(private val previous:ProcessingTiming=ProcessingTiming(),private val clock:()->Long=System::nanoTime) {
    private val start=clock()
    private var value=previous
    fun add(stage:ProcessingStage,seconds:Double) {
        value=when(stage) {
            ProcessingStage.RECOGNITION -> value.copy(recognition=(value.recognition ?: 0.0)+seconds)
            ProcessingStage.TRANSLATION -> value.copy(translation=(value.translation ?: 0.0)+seconds)
            ProcessingStage.SYNTHESIS -> value.copy(synthesis=(value.synthesis ?: 0.0)+seconds)
            ProcessingStage.MODEL_LOAD -> value.copy(modelLoad=(value.modelLoad ?: 0.0)+seconds)
        }
    }
    fun snapshot()=value.copy(total=previous.total+(clock()-start).coerceAtLeast(0)/1e9)
}
