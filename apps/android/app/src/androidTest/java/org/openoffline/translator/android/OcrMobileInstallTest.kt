package org.openoffline.translator.android

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.*
import java.io.File

/** Explicit opt-in installation of the previously benchmarked public fixture.
 * Uses the production size/hash validation and atomic import; no other models removed. */
@RunWith(AndroidJUnit4::class)
class OcrMobileInstallTest {
    @Test fun importValidatedMobileDetector() {
        val inst=InstrumentationRegistry.getInstrumentation()
        check(InstrumentationRegistry.getArguments().getString("installOcrMobile")=="true") { "Requires explicit installOcrMobile=true" }
        val repo=PackageDownloads.repository(inst.targetContext)
        runBlocking { withTimeout(60_000) { repo.restored.first { it } } }
        if(repo.installedPath("ppocr-v5-mobile-det")!=null)return
        val fixture=File(inst.targetContext.noBackupFilesDir,"ocr-research/mobile.onnx")
        repo.importFile("ppocr-v5-mobile-det",Uri.fromFile(fixture))
        runBlocking { withTimeout(60_000) {
            repo.states.first { it["ppocr-v5-mobile-det"]?.phase in setOf(PackagePhase.INSTALLED,PackagePhase.ERROR) }
        } }
        assertNotNull(repo.states.value.toString(),repo.installedPath("ppocr-v5-mobile-det"))
    }
}
