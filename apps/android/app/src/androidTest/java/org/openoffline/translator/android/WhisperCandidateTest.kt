package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.OfflineMedia
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Opt-in research only. No catalog/default/preferences/history changes or network.
 * Import: -e candidate tiny|base -e fixtureRoot /data/local/tmp/kat-asr-research
 * then select one benchmark method. Same native API and synthetic EN fixture as
 * MediaPipelineTest#asr. No Activity: compare to that baseline, not UI latency. */
@RunWith(AndroidJUnit4::class)
class WhisperCandidateTest {
    private val inst get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=inst.targetContext
    private data class Candidate(val bytes:Long,val sha256:String)
    private val candidates=mapOf(
        "tiny" to Candidate(77691713,"be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
        "base" to Candidate(147951465,"60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"))
    private fun destination(id:String)=File(File(context.noBackupFilesDir,"asr-research"),"ggml-$id.bin")
    private fun report(value:JSONObject) { inst.sendStatus(0,Bundle().apply { putString("stream","\nASR_CANDIDATE $value\n") }) }
    private fun sha(file:File):String {
        val digest=MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(1024*1024).use { input -> val bytes=ByteArray(1024*1024);while(true){val n=input.read(bytes);if(n<0)break;digest.update(bytes,0,n)} }
        return digest.digest().joinToString(""){"%02x".format(it)}
    }
    @Test fun importCandidate() {
        val args=InstrumentationRegistry.getArguments()
        val id=requireNotNull(args.getString("candidate")){"Pass -e candidate tiny or base"}
        val spec=requireNotNull(candidates[id]){"Only pinned multilingual tiny/base research candidates are accepted"}
        val source=args.getString("fixtureRoot","/data/local/tmp/kat-asr-research")!!.trimEnd('/')+"/ggml-$id.bin"
        require(source.startsWith("/data/local/tmp/") && !source.contains('\u0000'))
        val target=destination(id);check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        val temporary=File(target.parentFile,".$id.partial")
        check(target.parentFile!!.usableSpace>spec.bytes+32L*1024*1024)
        try {
            val pipes=inst.uiAutomation.executeShellCommandRw("sh")
            ParcelFileDescriptor.AutoCloseInputStream(pipes[0]).use { input ->
                ParcelFileDescriptor.AutoCloseOutputStream(pipes[1]).use { command ->
                    val quoted="'"+source.replace("'","'\\''")+"'"
                    command.write("exec cat $quoted\n".toByteArray(Charsets.UTF_8))
                }
                FileOutputStream(temporary).use { output ->
                    var count=0L;val buffer=ByteArray(1024*1024)
                    while(true) { val n=input.read(buffer);if(n<0)break;count+=n;check(count<=spec.bytes){"Fixture exceeds pinned size"};output.write(buffer,0,n) }
                    output.fd.sync();assertEquals(spec.bytes,count)
                }
            }
            assertEquals(spec.sha256,sha(temporary))
            check(temporary.renameTo(target)){"Could not publish app-owned research model"}
            report(JSONObject().put("imported",id).put("bytes",target.length()).put("sha256",spec.sha256))
        } finally { temporary.delete() }
    }
    @Test(timeout=120000) fun tinyEnglish()=benchmark("tiny","en")
    @Test(timeout=120000) fun tinyRussian()=benchmark("tiny","ru")
    @Test(timeout=120000) fun baseEnglish()=benchmark("base","en")
    @Test(timeout=120000) fun baseRussian()=benchmark("base","ru")
    private fun benchmark(id:String,language:String) {
        val model=destination(id);val spec=candidates.getValue(id)
        assertTrue("Run importCandidate for $id first",model.isFile)
        assertEquals(spec.bytes,model.length());assertEquals(spec.sha256,sha(model))
        val info=JSONObject(inst.context.assets.open("media-asr-$language.json").bufferedReader().use{it.readText()})
        val fixture=File.createTempFile("asr-candidate-",".wav",context.cacheDir)
        try {
            inst.context.assets.open("media-asr-$language.fixture").use { input -> fixture.outputStream().use{input.copyTo(it)} }
            assertEquals(info.getString("sha256"),sha(fixture))
            val samples=AudioImport.decode(context,Uri.fromFile(fixture)){false}
            val reference=info.getString("text")
            val deadline=InstrumentationRegistry.getArguments().getString("candidateTimeoutSeconds","30")!!.toLong()
            require(deadline in 1..60)
            val timedOut=AtomicBoolean(false)
            val timer=Executors.newSingleThreadScheduledExecutor()
            OfflineMedia().use { media ->
                val cancellation=timer.schedule({timedOut.set(true);media.cancel()},deadline,TimeUnit.SECONDS)
                val start=SystemClock.elapsedRealtimeNanos()
                try {
                    val transcript=media.transcribe(model.path,samples,language)
                    val seconds=(SystemClock.elapsedRealtimeNanos()-start)/1e9
                    val actual=words(transcript.text);val expected=words(reference)
                    val keywords=if(language=="en")listOf("not","cancel","order","train") else listOf("голос","поезд","отправ","пять")
                    val missing=keywords.filter{key->actual.none{it.contains(key) || (key=="пять" && it=="5")}}
                    report(JSONObject().put("candidate",id).put("language",language).put("recognizedLanguage",transcript.language)
                        .put("seconds",seconds).put("audioSeconds",samples.size/16000.0).put("rtf",seconds/(samples.size/16000.0))
                        .put("wordErrorRate",distance(expected,actual).toDouble()/expected.size)
                        .put("criticalWordsMissing",missing.joinToString(",")).put("text",transcript.text).put("reference",reference)
                        .put("timedOut",timedOut.get()).put("includesModelLoad",true).put("execution","instrumentation-no-activity"))
                    assertFalse("Candidate exceeded ${deadline}s budget",timedOut.get())
                    assertEquals(language,transcript.language)
                    assertTrue("Missing critical words $missing: ${transcript.text}",missing.isEmpty())
                } catch(error:Exception) {
                    report(JSONObject().put("candidate",id).put("language",language).put("seconds",(SystemClock.elapsedRealtimeNanos()-start)/1e9)
                        .put("timedOut",timedOut.get()).put("error",error.message ?: error.javaClass.simpleName))
                    throw error
                } finally { cancellation.cancel(false);timer.shutdownNow() }
            }
        } finally { fixture.delete() }
    }
    private fun words(text:String)=text.lowercase(Locale.ROOT).replace('ё','е').split(Regex("[^\\p{L}\\p{N}]+" )).filter{it.isNotEmpty()}
    private fun distance(a:List<String>,b:List<String>):Int {
        var previous=IntArray(b.size+1){it}
        for(i in a.indices) { val row=IntArray(b.size+1);row[0]=i+1
            for(j in b.indices)row[j+1]=minOf(previous[j+1]+1,row[j]+1,previous[j]+if(a[i]==b[j])0 else 1)
            previous=row
        }
        return previous[b.size]
    }
}
