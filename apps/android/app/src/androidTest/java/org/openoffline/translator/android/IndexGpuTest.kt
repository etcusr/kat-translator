package org.openoffline.translator.android

import android.content.Intent
import android.os.Bundle
import android.os.Debug
import android.view.WindowManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.*
import java.io.File

@RunWith(AndroidJUnit4::class)
class IndexGpuTest {
    @Test fun realVulkanIndexTranslation() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val context=inst.targetContext
        val args=InstrumentationRegistry.getArguments()
        val corpusOnly=args.getString("corpusOnly","false").toBoolean()
        val corpusCase=args.getString("corpusCase","")
        require(!corpusOnly || args.getString("corpus","false").toBoolean())
        val stockMmvq=args.getString("stockMmvq","false").toBoolean()
        if(stockMmvq)android.system.Os.setenv("KAT_VK_STOCK_G715_MMVQ","1",true)
        val stockPrefill=args.getString("stockPrefill","false").toBoolean()
        if(stockPrefill)android.system.Os.setenv("KAT_VK_STOCK_G715_PREFILL","1",true)
        val profile=args.getString("profile", "none")
        require(profile in setOf("none","timings","gpu","gpu-concurrent"))
        if(profile!="none") {
            val fd=android.system.Os.open(File(context.filesDir,"index-profile.log").path,android.system.OsConstants.O_CREAT or android.system.OsConstants.O_WRONLY or android.system.OsConstants.O_TRUNC,384)
            android.system.Os.dup2(fd,2);android.system.Os.close(fd)
            android.system.Os.setenv("KAT_INDEX_PROFILE","1",true)
            if(profile.startsWith("gpu")) {
                android.system.Os.setenv("GGML_VK_PERF_LOGGER","1",true)
                android.system.Os.setenv("GGML_VK_PERF_LOGGER_FREQUENCY","1",true)
                if(profile=="gpu-concurrent")android.system.Os.setenv("GGML_VK_PERF_LOGGER_CONCURRENT","1",true)
            }
        }
        val flash=args.getString("flash","true").toBoolean()
        val mtp=args.getString("mtp","true").toBoolean()
        val narrowTiles=args.getString("maliNarrowTiles","true").toBoolean()
        if(!narrowTiles)android.system.Os.setenv("KAT_VK_ALLOW_NARROW_TILES","1",true)
        val stockCoop=args.getString("stockCoopmat","false").toBoolean()
        if(stockCoop)android.system.Os.setenv("KAT_VK_ENABLE_G715_COOPMAT","1",true)
        val disabled=args.getString("vkDisable","").split(',').filter { it.isNotBlank() }
        disabled.forEach { feature ->
            require(feature in setOf("GRAPH_OPTIMIZE","DESCRIPTOR_REUSE","FUSION","COOPMAT","ASYNC","INTEGER_DOT_PRODUCT","MMVQ"))
            android.system.Os.setenv("GGML_VK_DISABLE_$feature","1",true)
        }
        val activity=inst.startActivitySync(Intent(context,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        inst.waitForIdleSync()
        inst.runOnMainSync { activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
        fun stage(s:String) { inst.sendStatus(0,Bundle().apply { putString("stream","\nVulkan: $s\n") }) }
        val rows=JSONArray()
        val report=JSONObject().put("backend","vulkan").put("flashAttention",flash).put("threads",4).put("context",2048).put("cases",rows).put("passed",false)
        report.put("disabledOptimizations",JSONArray(disabled))
        report.put("profile",profile)
        report.put("mtpEnabled",mtp)
        report.put("stockG715Mmvq",stockMmvq)
        report.put("stockG715Prefill",stockPrefill)
        report.put("maliNarrowTiles",narrowTiles)
        report.put("g715CooperativeMatrix",stockCoop && "COOPMAT" !in disabled)
        val file=File(context.getExternalFilesDir(null),"index-vulkan-$flash.json")
        try {
            val name=IndexEngine.gpuName();report.put("gpu",name);stage("GPU: $name")
            assertTrue("A real GPU must be present; CPU fallback is not accepted",name.contains("Mali"))
            val model=File(context.getExternalFilesDir(null),"Index-Translate-9B.Q4_K_M.gguf")
            assertEquals(5780090304L,model.length())
            stage("checking model hash")
            val hash=java.security.MessageDigest.getInstance("SHA-256")
            model.inputStream().use { stream -> val buffer=ByteArray(1024*1024);while(true) { val n=stream.read(buffer);if(n<0)break;hash.update(buffer,0,n) } }
            val digest=hash.digest().joinToString("") { "%02x".format(it) }
            assertEquals("9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713",digest)
            report.put("sha256",digest)
            stage("loading full model on GPU")
            val begin=System.nanoTime()
            IndexEngine.open(model.path,gpu=true,flash=flash,mtp=mtp).use { engine ->
                report.put("loadSeconds",(System.nanoTime()-begin)/1e9);file.writeText(report.toString(2))
                stage("loaded; checking tokenizer parity")
                val fixtures=JSONObject(inst.context.assets.open("index-token-parity.json").bufferedReader().use { it.readText() }).getJSONArray("cases")
                for(i in 0 until fixtures.length()) { val f=fixtures.getJSONObject(i);val ids=f.getJSONArray("tokens");assertArrayEquals(IntArray(ids.length()) { ids.getInt(it) },engine.tokens(IndexRequest(f.getString("text"),f.getString("target")))) }
                report.put("tokenParityCases",fixtures.length())
                repeat(if(corpusOnly) 0 else 3) { iteration ->
                    val input="Привет! Встреча завтра в 15:30."
                    stage("translation ${iteration+1}/3")
                    val start=System.nanoTime()
                    val pool=java.util.concurrent.Executors.newSingleThreadExecutor()
                    val result=try {
                        val future=pool.submit<TranslationResult> { engine.translate(IndexRequest(input,"en")) }
                        try { future.get(60,java.util.concurrent.TimeUnit.SECONDS) }
                        catch(e:java.util.concurrent.TimeoutException) { engine.cancel();future.get(15,java.util.concurrent.TimeUnit.SECONDS);throw AssertionError("GPU translation exceeded 60 seconds; cancelled") }
                    } finally { pool.shutdownNow() }
                    val seconds=(System.nanoTime()-start)/1e9
                    assertTrue("Expected GPU translation success, got $result",result is TranslationResult.Success)
                    result as TranslationResult.Success
                    assertTrue(result.text,(result.text.contains("15:30") || Regex("3:30\\s*PM",RegexOption.IGNORE_CASE).containsMatchIn(result.text)) && result.text.contains("tomorrow",true))
                    val memory=Debug.MemoryInfo();Debug.getMemoryInfo(memory)
                    rows.put(JSONObject().put("input",input).put("target","en").put("output",result.text).put("seconds",seconds).put("firstTokenSeconds",result.firstTokenSeconds).put("draftedTokens",result.draftedTokens).put("acceptedTokens",result.acceptedTokens).put("pssKiB",memory.totalPss).put("thermalStatus",context.getSystemService(android.os.PowerManager::class.java).currentThermalStatus))
                    stage("result: $seconds s; first token ${result.firstTokenSeconds} s; ${result.text}")
                    file.writeText(report.toString(2))
                }
                if(!corpusOnly) {
                    val result=engine.translate(IndexRequest("The train leaves at 10:30.","ru"))
                    assertTrue(result is TranslationResult.Success && result.text.contains("10:30") && result.text.any { it in 'А'..'я' })
                    report.put("reverseTranslationPassed",true)
                }
                if(args.getString("corpus","false").toBoolean()) {
                    val corpus=JSONObject(inst.context.assets.open("index-gpu-corpus.json").bufferedReader().use { it.readText() }).getJSONArray("cases")
                    val corpusRows=JSONArray();report.put("corpus",corpusRows)
                    for(i in 0 until corpus.length()) {
                        val fixture=corpus.getJSONObject(i)
                        if(corpusCase.isNotEmpty() && fixture.getString("id")!=corpusCase)continue
                        val request=IndexRequest(fixture.getString("text"),fixture.getString("target"))
                        stage("corpus ${i+1}/${corpus.length()}: ${fixture.getString("id")}")
                        val row=JSONObject().put("id",fixture.getString("id")).put("input",request.text).put("target",request.target).put("promptTokens",engine.tokens(request).size)
                        corpusRows.put(row);file.writeText(report.toString(2))
                        val start=System.nanoTime()
                        val pool=java.util.concurrent.Executors.newSingleThreadExecutor()
                        val translated=try {
                            val future=pool.submit<TranslationResult> { engine.translate(request) }
                            try { future.get(120,java.util.concurrent.TimeUnit.SECONDS) }
                            catch(e:java.util.concurrent.TimeoutException) { engine.cancel();future.get(30,java.util.concurrent.TimeUnit.SECONDS);throw AssertionError("Corpus translation exceeded 120 seconds") }
                        } finally { pool.shutdownNow() }
                        row.put("seconds",(System.nanoTime()-start)/1e9).put("thermalStatus",context.getSystemService(android.os.PowerManager::class.java).currentThermalStatus)
                        assertTrue("$request: $translated",translated is TranslationResult.Success)
                        translated as TranslationResult.Success
                        row.put("output",translated.text).put("firstTokenSeconds",translated.firstTokenSeconds).put("draftedTokens",translated.draftedTokens).put("acceptedTokens",translated.acceptedTokens)
                        file.writeText(report.toString(2))
                        val checks=fixture.getJSONArray("patterns")
                        for(j in 0 until checks.length()) assertTrue("${fixture.getString("id")}: missing ${checks.getString(j)} in ${translated.text}",Regex(checks.getString(j),RegexOption.IGNORE_CASE).containsMatchIn(translated.text))
                        row.put("passed",true)
                    }
                    assertTrue("No corpus cases selected",corpusRows.length()>0)
                    report.put("corpusPassed",true)
                }
            }
            report.put("passed",true)
        } finally { file.writeText(report.toString(2));inst.runOnMainSync { activity.finish() } }
    }
}
