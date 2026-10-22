package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test
import org.openoffline.translator.android.packages.PackageCatalog
import java.io.File

class MissingPackageTest {
    @Test fun absentPackageCarriesItsIdForTheDownloadNotice() {
        val error=assertThrows(MissingPackageException::class.java) { requirePackagePath("ppocr-v5-mobile-det",null) { "Install the OCR text detector in Models." } }
        assertEquals(listOf("ppocr-v5-mobile-det"),error.ids)
        assertEquals("Install the OCR text detector in Models.",error.message)
        val path=File("installed")
        assertSame(path,requirePackagePath("any",path) { "unused" })
    }
    @Test fun translationHintDownloadsThePairPackage() {
        assertEquals(PackageCatalog.INDEX_ID,translationPackageFor("index",null))
        assertEquals(PackageCatalog.INDEX2B_ID,translationPackageFor("index2b","opus-route"))
        assertEquals("opus-mt-de-en",translationPackageFor("opus","opus-mt-de-en"))
        assertEquals(PackageCatalog.INDEX2B_ID,translationPackageFor("opus",null))
        assertNull(translationPackageFor("unknown",null))
    }
    @Test fun noticeActionsAreLocalized() {
        assertEquals("Download",UiStrings.text("Скачать",language="en"))
        assertEquals("Descargando Index 2B · 40%",UiStrings.text("Скачиваю %@ · %@%",null,"es","Index 2B",40))
    }
}
