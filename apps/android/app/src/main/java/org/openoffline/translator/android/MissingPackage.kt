package org.openoffline.translator.android

import org.openoffline.translator.android.packages.PackageCatalog
import java.io.File

/** A model an error names; the notice downloads it instead of only pointing to Models. */
data class MissingPackage(val message:String,val ids:List<String>,val workspace:String)
internal class MissingPackageException(message:String,val ids:List<String>):IllegalStateException(message)

internal fun requirePackagePath(id:String,path:File?,message:()->String):File =
    path ?: throw MissingPackageException(message(),listOf(id))

/** The package that makes a translation model usable for the pair. A pair OPUS cannot cover
 * goes to Index 2B, the multilingual model Auto also falls back to. */
internal fun translationPackageFor(model:String,opusRoute:String?):String? = when(model) {
    "opus" -> opusRoute ?: PackageCatalog.INDEX2B_ID
    else -> PackageCatalog.INDEX_MODELS[model]?.second
}

/** Open OCR needs a text detector; the fast mobile detector is the one Models recommends. */
internal const val OCR_DETECTOR_DOWNLOAD="ppocr-v5-mobile-det"
