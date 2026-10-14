package org.openoffline.translator.android
import android.os.Bundle
import android.os.Debug
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import org.json.JSONArray
import org.openoffline.translator.inference.*
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class IndexDeviceTest {
    @get:org.junit.Rule val preferences = UiTestEnvironment.wrap()
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private val context=instrumentation.targetContext
    private val rows=JSONArray()
    private fun stage(name:String) { instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nIndex: $name\n") }) }
    private fun memoryKiB(): Int { val info=Debug.MemoryInfo();Debug.getMemoryInfo(info);return info.totalPss }
    @Test fun realIndexAcceptance() {
        val gpu=InstrumentationRegistry.getArguments().getString("gpu","true").toBoolean()
        val activity=instrumentation.startActivitySync(android.content.Intent(context,MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.runOnMainSync { activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
        val report=JSONObject().put("model",Build.MODEL).put("android",Build.VERSION.RELEASE).put("sdk",Build.VERSION.SDK_INT).put("backend",if(gpu)"vulkan" else "cpu").put("threads",4).put("cases",rows).put("passed",false)
        val reportFile=File(context.getExternalFilesDir(null),"index-acceptance.json")
        var engine:IndexEngine?=null
        try {
            val model=File(context.getExternalFilesDir(null),"Index-Translate-9B.Q4_K_M.gguf")
            assertTrue("Real Index model is required; missing model is a failure",model.isFile)
            assertEquals(5780090304L,model.length())
            stage("SHA-256")
            val hash=MessageDigest.getInstance("SHA-256");val buffer=ByteArray(1024*1024)
            model.inputStream().use { stream -> while(true) { val n=stream.read(buffer);if(n<0)break;hash.update(buffer,0,n) } }
            val digest=hash.digest().joinToString("") { "%02x".format(it) }
            assertEquals("9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713",digest);report.put("sha256",digest)
            stage("load")
            val begin=System.nanoTime();engine=IndexEngine.open(model.path,gpu=gpu,flash=gpu)
            report.put("loadSeconds",(System.nanoTime()-begin)/1e9).put("loadedPssKiB",memoryKiB())
            stage("token parity / literal controls / Unicode")
            val fixtures=JSONObject(instrumentation.context.assets.open("index-token-parity.json").bufferedReader().use { it.readText() }).getJSONArray("cases")
            for(i in 0 until fixtures.length()) {
                val f=fixtures.getJSONObject(i);val request=IndexRequest(f.getString("text"),f.getString("target"));val expected=f.getJSONArray("tokens")
                assertEquals(f.getString("prefix"),request.prefix);assertEquals(f.getString("suffix"),request.suffix)
                assertArrayEquals(IntArray(expected.length()) { expected.getInt(it) },engine.tokens(request))
            }
            report.put("tokenParityCases",fixtures.length())
            fun translate(text:String,target:String):String {
                stage("translate $target")
                val start=System.nanoTime();val result=engine!!.translate(IndexRequest(text,target))
                assertTrue("Expected Success, got $result",result is TranslationResult.Success);result as TranslationResult.Success
                assertTrue(result.text.isNotBlank())
                rows.put(JSONObject().put("input",text).put("target",target).put("output",result.text).put("seconds",(System.nanoTime()-start)/1e9).put("firstTokenSeconds",result.firstTokenSeconds).put("pssKiB",memoryKiB()))
                reportFile.writeText(report.toString(2));return result.text
            }
            val english=translate("Встреча завтра в 15:30.","en");assertTrue(english.contains("15:30") || Regex("3:30\\s*PM",RegexOption.IGNORE_CASE).containsMatchIn(english));assertTrue(english.any { it in 'A'..'Z' || it in 'a'..'z' })
            val russian=translate("The train leaves at 10:30.","ru");assertTrue(russian.contains("10:30"));assertTrue(russian.any { it in 'А'..'я' })
            stage("input / output limits")
            assertEquals(TranslationResult.Limit,engine.translate(IndexRequest("word ".repeat(2000),"ru")))
            assertEquals(TranslationResult.Limit,engine.translate(IndexRequest("Hello, world!","ru"),outputBytes=1))
            stage("cancel then new request")
            val pool=Executors.newSingleThreadExecutor()
            try {
                val future=pool.submit<TranslationResult> { engine!!.translate(IndexRequest("The meeting is tomorrow at 10:30. ".repeat(30),"ru")) }
                Thread.sleep(800) // Exercise cancellation after GPU work has begun.
                val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(20)
                var cancelled=false
                while(!cancelled && !future.isDone && System.nanoTime()<deadline) { cancelled=engine.cancel();if(!cancelled)Thread.sleep(10) }
                assertTrue("Native request never became cancellable",cancelled)
                assertEquals(TranslationResult.Cancelled,future.get(60,TimeUnit.SECONDS))
            } finally { pool.shutdownNow() }
            translate("Спасибо!","en")
            stage("close / reload")
            engine.close();engine=null
            IndexEngine.open(model.path,gpu=gpu,flash=gpu).use { assertTrue(it.tokens(IndexRequest("Hello","ru")).isNotEmpty()) }
            report.put("passed",true).put("limitsPassed",true).put("cancelThenNewRequestPassed",true).put("reloadPassed",true)
        } finally { engine?.close();reportFile.writeText(report.toString(2));instrumentation.runOnMainSync { activity.finish() } }
    }
}
