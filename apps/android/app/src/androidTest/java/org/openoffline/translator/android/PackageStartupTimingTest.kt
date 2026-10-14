package org.openoffline.translator.android
import androidx.test.platform.app.InstrumentationRegistry
import org.openoffline.translator.android.packages.PackageDownloads
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.first
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
class PackageStartupTimingTest {
    @Test fun unchangedInstalledPackagesUseReceiptsWithoutHashingModelWeights()=runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val repository=PackageDownloads.repository(context)
        withTimeout(30_000) { repository.restored.first { it } }
        val report=JSONObject().put("seconds",repository.restorationSeconds).put("cachedPackages",repository.startupCachedPackages).put("fullVerifications",repository.startupFullVerifications)
        File(context.filesDir,"package-startup-timing.json").writeText(report.toString(2))
        assertTrue(repository.startupCachedPackages>0)
        assertEquals("Unchanged installed models must not be hashed on startup",0,repository.startupFullVerifications)
    }
}
