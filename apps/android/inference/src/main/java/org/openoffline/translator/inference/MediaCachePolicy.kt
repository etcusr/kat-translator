package org.openoffline.translator.inference

/** Cache is optional: small phones and low headroom retain the prior per-operation lifetime. */
object MediaCachePolicy {
    fun retain(total:Long,available:Long,lowMemoryThreshold:Long,saving:Boolean):Boolean =
        !saving && total>=11_500_000_000L && available>=maxOf(2_000_000_000L,lowMemoryThreshold*2)
}
