package org.openoffline.translator.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.*
import java.io.File

/** Run control and MTP separately through the thermal guard; compare the real outputs. */
@RunWith(AndroidJUnit4::class)
class IndexMtpTest {
    @Test fun exactGreedyParity() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val args=InstrumentationRegistry.getArguments()
        val mtp=args.getString("mtp","true").toBoolean()
        val id=args.getString("case","short")
        require(id in setOf("short","medium"))
        val request=if(id=="short")IndexRequest("Привет! Встреча завтра в 15:30.","en") else {
            val rows=JSONObject(inst.context.assets.open("index-gpu-corpus.json").bufferedReader().use{it.readText()}).getJSONArray("cases")
            val row=(0 until rows.length()).map{rows.getJSONObject(it)}.first{it.getString("id")=="medium-en-ru"}
            IndexRequest(row.getString("text"),row.getString("target"))
        }
        val dir=inst.targetContext.getExternalFilesDir(null)!!
        val file=File(dir,"mtp-$id-$mtp.json")
        val report=JSONObject().put("passed",false).put("mtp",mtp).put("case",id)
        try {
            val model=File(dir,"Index-Translate-9B.Q4_K_M.gguf")
            assertEquals(5780090304L,model.length())
            IndexEngine.open(model.path,mtp=mtp).use { engine ->
                assertEquals(mtp,engine.mtpEnabled)
                val begin=System.nanoTime()
                val result=engine.translate(request)
                assertTrue("$result",result is TranslationResult.Success)
                result as TranslationResult.Success
                report.put("seconds",(System.nanoTime()-begin)/1e9).put("firstTokenSeconds",result.firstTokenSeconds)
                    .put("output",result.text).put("drafted",result.draftedTokens).put("accepted",result.acceptedTokens)
                if(mtp) {
                    val control=JSONObject(File(dir,"mtp-$id-false.json").readText())
                    assertTrue("A passing control run is required",control.getBoolean("passed"))
                    assertEquals(control.getString("output"),result.text)
                    assertTrue("Draft block must actually run",result.draftedTokens>0)
                    assertTrue(result.acceptedTokens in 1..result.draftedTokens)
                    if(id=="medium")assertTrue("Fixture must exercise rejected drafts",result.acceptedTokens<result.draftedTokens)
                } else assertEquals(0,result.draftedTokens)
            }
            report.put("passed",true)
        } finally { file.writeText(report.toString(2)) }
    }
}
