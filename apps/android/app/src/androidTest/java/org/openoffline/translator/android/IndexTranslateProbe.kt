package org.openoffline.translator.android

import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog
import org.openoffline.translator.android.packages.PackageRepository
import org.openoffline.translator.inference.IndexEngine
import org.openoffline.translator.inference.IndexRequest
import org.openoffline.translator.inference.TranslationResult
import java.io.File

/** Opt-in: translates "id|text" lines from a file in the app cache with the installed Index model.
 * Arguments: file, target (default en), model (2b/9b). Prints results only; no content assertion. */
@RunWith(AndroidJUnit4::class)
class IndexTranslateProbe {
    @get:Rule val environment=UiTestEnvironment.wrap()
    private val inst get()=InstrumentationRegistry.getInstrumentation()

    @Test(timeout=900000) fun translate() {
        val args=InstrumentationRegistry.getArguments()
        val name=args.getString("file");assumeTrue("file argument required",name!=null)
        val target=args.getString("target") ?: "en"
        val id=if(args.getString("model")=="9b")PackageCatalog.INDEX_ID else PackageCatalog.INDEX2B_ID
        val context=inst.targetContext
        val store=PackageRepository(context)
        // Receipts are verified asynchronously after the repository starts.
        val deadline=SystemClock.elapsedRealtime()+180_000
        var installed=store.installedPath(id)
        while(installed==null && SystemClock.elapsedRealtime()<deadline) { Thread.sleep(100);installed=store.installedPath(id) }
        val path=checkNotNull(installed) { "$id is not installed" }
        val lines=File(context.cacheDir,name!!).readLines().filter { it.contains('|') }
        store.acquire(id).use {
            IndexEngine.open(path.path,gpu=true,flash=true,mtp=false).use { engine ->
                for(line in lines) {
                    val (key,text)=line.split('|',limit=2)
                    val begin=SystemClock.elapsedRealtimeNanos()
                    val result=engine.translate(IndexRequest(text,target))
                    val output=(result as? TranslationResult.Success)?.text ?: result.toString()
                    val row=JSONObject().put("id",key).put("seconds",(SystemClock.elapsedRealtimeNanos()-begin)/1e9).put("text",output)
                    inst.sendStatus(0,Bundle().apply { putString("stream","\nINDEX_PROBE $row\n") })
                }
            }
        }
    }
}
