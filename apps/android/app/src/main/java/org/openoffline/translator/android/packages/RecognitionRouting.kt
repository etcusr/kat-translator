package org.openoffline.translator.android.packages

/** One language policy for preparation, live phrases, complete recordings and file import.
 * Missing weights must not silently change engines or select another Parakeet version. */
object RecognitionRouting {
    fun requiredId(language:String):String=when(language) {
        "ru" -> "gigaam-v3-int8"
        "en" -> "parakeet-v2-en-int8"
        else -> "whisper-large-v3-turbo-q8_0"
    }
    fun recommended(catalog:List<OfflinePackage>,language:String):OfflinePackage? {
        return catalog.firstOrNull { it.id==requiredId(language) && it.category==PackageCategory.RECOGNITION &&
            (language=="auto" || it.supports(language)) && it.unavailableReason==null }
    }
}
