package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Opt-in real platform-service tests. Root grants RECORD_AUDIO; no network/model downloads.
 * Synthetic fixtures only. Activity keeps service access foreground; automatic model loading
 * is disabled/restored by the existing test rule. Run FILE methods first, pipe only explicitly. */
@RunWith(AndroidJUnit4::class)
class PlatformSpeechAudioTest {
    private val activity=ActivityScenarioRule(MainActivity::class.java)
    @get:Rule val environment=UiTestEnvironment.wrap(activity)
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=inst.targetContext

    @Test(timeout=65000) fun fileEnglish()=recognize("en","en")
    @Test(timeout=65000) fun fileRussian()=recognize("ru","ru")
    @Test(timeout=65000) fun fileAutoEnglish()=recognize("en","auto")
    @Test(timeout=65000) fun fileAutoRussian()=recognize("ru","auto")
    @Test(timeout=65000) fun pacedEnglish()=recognize("en","en",SystemSpeechRecognizer.InputMode.PACED_PIPE)
    @Test(timeout=65000) fun pacedRussian()=recognize("ru","ru",SystemSpeechRecognizer.InputMode.PACED_PIPE)

    @Test(timeout=120000) fun multipleUtterancesIncludeTheLastSentence() {
        val phrase=fixture("ru")
        val pause=FloatArray(16000)
        val samples=phrase+pause+phrase+pause+phrase
        val result=SystemSpeechRecognizer(context,timeoutMillis=110000).use { it.transcribe(samples,"ru") { false } }
        report(JSONObject().put("case","three-utterances").put("text",result.text).put("audioSeconds",samples.size/16000.0))
        assertEquals("Every repeated sentence must survive, including the final one: ${result.text}",3,
            Regex("поезд",RegexOption.IGNORE_CASE).findAll(result.text).count())
    }
    @Test(timeout=65000) fun cancellationThenReuse() {
        val samples=fixture("en")
        SystemSpeechRecognizer(context).use { recognizer ->
            val timer=Executors.newSingleThreadScheduledExecutor()
            val begin=SystemClock.elapsedRealtime()
            try {
                // Long synthetic silence keeps a real input session alive beyond cancellation.
                val cancel=timer.schedule({recognizer.cancel()},250,TimeUnit.MILLISECONDS)
                try { recognizer.transcribe(FloatArray(16000*60),"en"){false};fail("Cancellation must not return a transcript") }
                catch(expected:CancellationException) {
                    report(JSONObject().put("case","cancel").put("milliseconds",SystemClock.elapsedRealtime()-begin))
                    assertTrue("Cancel must return promptly",SystemClock.elapsedRealtime()-begin<3000)
                } finally { cancel.cancel(false) }
                val result=recognizer.transcribe(samples,"en"){false}
                assertTrue(result.text,result.text.contains("cancel",true))
                report(JSONObject().put("case","reuse").put("text",result.text).put("language",result.language))
            } finally { timer.shutdownNow() }
        }
    }
    private fun recognize(language:String,source:String,mode:SystemSpeechRecognizer.InputMode=SystemSpeechRecognizer.InputMode.FILE) {
        val samples=fixture(language)
        val reference=JSONObject(inst.context.assets.open("media-asr-$language.json").bufferedReader().use { it.readText() }).getString("text")
        val begin=SystemClock.elapsedRealtimeNanos()
        SystemSpeechRecognizer(context,mode).use { recognizer ->
            try {
                val result=recognizer.transcribe(samples,source){false}
                val seconds=(SystemClock.elapsedRealtimeNanos()-begin)/1e9
                val words=result.text.lowercase(Locale.ROOT).replace('ё','е').split(Regex("[^\\p{L}\\p{N}]+" )).filter { it.isNotEmpty() }
                val required=if(language=="en")listOf("not","cancel","order","train") else listOf("здравствуйте","так","звучит","мой","голос","поезд","отправляется","в","часов")
                val missing=required.filter { key -> words.none { it == key } }.toMutableList()
                if(language=="ru" && words.none { it=="пять" || it=="5" })missing+="пять/5"
                report(JSONObject().put("case","recognize").put("mode",mode.name).put("source",source)
                    .put("expectedLanguage",language).put("recognizedLanguage",result.language).put("text",result.text)
                    .put("seconds",seconds).put("audioSeconds",samples.size/16000.0).put("rtf",seconds/(samples.size/16000.0))
                    .put("missing",missing.joinToString(",")).put("reference",reference)
                    .put("wordErrorRate",wordErrorRate(reference,result.text)))
                assertEquals(language,result.language)
                assertTrue("Missing $missing: ${result.text}",missing.isEmpty())
            } catch(error:Exception) {
                report(JSONObject().put("case","recognize").put("mode",mode.name).put("source",source)
                    .put("seconds",(SystemClock.elapsedRealtimeNanos()-begin)/1e9).put("error",error.toString()))
                throw error
            }
        }
    }
    // Keep raw numeric formatting differences visible even though the semantic assertion accepts 5.
    private fun wordErrorRate(reference:String,actual:String):Double {
        fun words(text:String)=text.lowercase(Locale.ROOT).replace('ё','е').split(Regex("[^\\p{L}\\p{N}]+" )).filter { it.isNotEmpty() }
        val a=words(reference);val b=words(actual)
        var previous=IntArray(b.size+1){it}
        for(i in a.indices) {
            val row=IntArray(b.size+1);row[0]=i+1
            for(j in b.indices)row[j+1]=minOf(previous[j+1]+1,row[j]+1,previous[j]+if(a[i]==b[j])0 else 1)
            previous=row
        }
        return previous[b.size].toDouble()/a.size.coerceAtLeast(1)
    }
    private fun fixture(language:String):FloatArray {
        val info=JSONObject(inst.context.assets.open("media-asr-$language.json").bufferedReader().use { it.readText() })
        val file=File.createTempFile("platform-speech-", ".wav",context.cacheDir)
        try {
            inst.context.assets.open("media-asr-$language.fixture").use { input -> file.outputStream().use { input.copyTo(it) } }
            val sha=MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString(""){"%02x".format(it)}
            assertEquals(info.getString("sha256"),sha)
            return AudioImport.decode(context,Uri.fromFile(file)){false}
        } finally { file.delete() }
    }
    private fun report(value:JSONObject) { inst.sendStatus(0,Bundle().apply { putString("stream","\nPLATFORM_SPEECH $value\n") }) }
}
