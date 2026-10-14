package org.openoffline.translator.android.packages

/** Selection depends on the explicit source language, never on installation order/readiness. */
object RecognitionRouting {
    fun recommended(catalog:List<OfflinePackage>,language:String):OfflinePackage? {
        val backend=if(language=="ru")"gigaam" else "parakeet"
        return catalog.firstOrNull { it.category==PackageCategory.RECOGNITION && it.backend==backend && it.supports(language) && it.unavailableReason==null }
    }
}
