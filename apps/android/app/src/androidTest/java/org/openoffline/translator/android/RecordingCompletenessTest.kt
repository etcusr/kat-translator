package org.openoffline.translator.android
import android.net.Uri
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
class RecordingCompletenessTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun externalRecordingIsFullyRecognized() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val args=InstrumentationRegistry.getArguments()
        val file=File(inst.targetContext.cacheDir,"asr-completeness.wav")
        org.junit.Assume.assumeTrue("Diagnostic recording was not supplied",file.isFile)
        val samples=AudioImport.decode(inst.targetContext,Uri.fromFile(file)) { false }
        val events=java.util.concurrent.CopyOnWriteArrayList<String>()
        val mode=if(args.getString("paced")=="true")SystemSpeechRecognizer.InputMode.PACED_PIPE else SystemSpeechRecognizer.InputMode.FILE
        val begin=android.os.SystemClock.elapsedRealtime()
        var recognized=""
        var failure:Throwable?=null
        try {
            recognized=SystemSpeechRecognizer(inst.targetContext,mode,120_000,events::add).use { it.transcribe(samples,"ru") { false } }.text
        } catch(error:Throwable) { failure=error }
        val report=JSONObject().put("seconds",(android.os.SystemClock.elapsedRealtime()-begin)/1000.0).put("audioSeconds",samples.size/16000.0)
            .put("text",recognized).put("events",JSONArray(events)).put("error",failure?.toString())
        File(inst.targetContext.cacheDir,"asr-completeness-result.json").writeText(report.toString(2))
        failure?.let { throw it }
        assertTrue("The complete recording must contain more than its first phrase",recognized.contains("озвуч",true) && recognized.contains("распознаван",true))
    }
}
