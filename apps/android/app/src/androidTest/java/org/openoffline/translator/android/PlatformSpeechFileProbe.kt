package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Opt-in measurement of the platform on-device recognizer on a WAV in the app's cache.
 * Arguments: wav (file name in cacheDir), lang (ru/en/...). Prints text and timing only; no assertion on content. */
@RunWith(AndroidJUnit4::class)
class PlatformSpeechFileProbe {
    private val activity=ActivityScenarioRule(MainActivity::class.java)
    @get:Rule val environment=UiTestEnvironment.wrap(activity)
    private val inst get()=InstrumentationRegistry.getInstrumentation()

    @Test(timeout=300000) fun measure() {
        val args=InstrumentationRegistry.getArguments()
        val name=args.getString("wav");assumeTrue("wav argument required",name!=null)
        val language=args.getString("lang") ?: "ru"
        val mode=SystemSpeechRecognizer.InputMode.valueOf(args.getString("mode") ?: "FILE")
        val context=inst.targetContext
        val samples=AudioImport.decode(context,Uri.fromFile(File(context.cacheDir,name!!))) { false }
        val begin=SystemClock.elapsedRealtimeNanos()
        val result=SystemSpeechRecognizer(context,mode,timeoutMillis=280000).use { it.transcribe(samples,language) { false } }
        val seconds=(SystemClock.elapsedRealtimeNanos()-begin)/1e9
        val line=JSONObject().put("mode",mode.name).put("lang",language).put("audioSeconds",samples.size/16000.0).put("seconds",seconds).put("text",result.text)
        inst.sendStatus(0,Bundle().apply { putString("stream","\nPLATFORM_PROBE $line\n") })
    }
}
