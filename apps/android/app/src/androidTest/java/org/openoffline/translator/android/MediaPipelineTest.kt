package org.openoffline.translator.android

import android.graphics.*
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.*
import org.openoffline.translator.android.packages.*
import java.io.File

/** Each method is run separately by the thermal guard. Verified shared packages only.
 * No network download, Activity launch, user preference or history mutation. */
@RunWith(AndroidJUnit4::class)
class MediaPipelineTest {
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=instrumentation.targetContext
    private var opened:PackageRepository?=null
    private val store:PackageRepository get()=opened?:PackageRepository(context).also{opened=it}
    @After fun close(){opened?.close()}
    private fun report(message:String){instrumentation.sendStatus(0,Bundle().apply{putString("stream",message+"\n")})}
    private fun path(id:String):File {
        val deadline=SystemClock.elapsedRealtime()+180000
        while(SystemClock.elapsedRealtime()<deadline){
            store.installedPath(id)?.let{return it}
            val status=store.states.value[id]
            check(status?.phase!=PackagePhase.ERROR){"Package $id failed verification: ${status?.message}"}
            Thread.sleep(100)
        }
        error("Install verified shared package $id before selecting this test")
    }
    private fun voice(id:String,text:String,language:String):SpeechAudio {
        val directory=path(id);val pack=store.catalog.single{it.id==id}
        val started=SystemClock.elapsedRealtime()
        val audio=store.acquire(id).use{OfflineMedia().use{engine->when(pack.backend){
            "piper","mms"->{val model=pack.files.first{it.path.endsWith(".onnx")}.path;val tokens=pack.files.first{it.path.endsWith("tokens.txt")}.path
                engine.synthesizePiper(File(directory,model).path,File(directory,tokens).path,File(directory,"espeak-ng-data").takeIf{it.isDirectory}?.path?:"",text)}
            "supertonic"->engine.synthesizeSupertonic(directory.path,text,pack.runtimeLanguage(language))
            "omnivoice"->engine.synthesizeOmniVoice(directory.path,text,pack.runtimeLanguage(language))
            "wayu"->engine.synthesizeWayu(WayuAssets.prepare(context),directory.path,text,"m_elderly_deep")
            else->error("Unsupported exact backend ${pack.backend}")
        }}}
        assertTrue(audio.samples.all{it.isFinite()})
        val energy=audio.samples.sumOf{it.toDouble()*it.toDouble()}
        assertTrue("Non-silent exact voice $id",energy>.001)
        assertTrue(audio.samples.size.toDouble()/audio.sampleRate in .1..60.0)
        val file=File(context.noBackupFilesDir,"media-acceptance-${pack.backend}.wav")
        SpeechPlayer.writeWav(file,audio)
        report("MEDIA_TTS id=$id backend=${pack.backend} rate=${audio.sampleRate} samples=${audio.samples.size} seconds=${(SystemClock.elapsedRealtime()-started)/1000.0} energy=$energy path=${file.path}")
        return audio
    }
    @Test fun piper(){voice("vits-piper-en_US-lessac-medium","Hello. Thank you.","en")}
    @Test fun supertonic(){voice("sherpa-onnx-supertonic-3-tts-int8-2026-05-11","Hello. Thank you.","en")}
    @Test fun wayu(){voice("wayu-prosody","ขอบคุณครับ","th")}
    @Test fun omniVoice(){voice("omnivoice-q8-base","Terima kasih.","ms")}
    @Test fun asr(){
        val id="whisper-large-v3-turbo-f16";val model=path(id)
        val bytes=instrumentation.context.assets.open("media-asr-en.fixture").use{it.readBytes()}
        fun word(i:Int)=(bytes[i].toInt() and 255) or ((bytes[i+1].toInt() and 255) shl 8)
        fun int(i:Int)=word(i) or (word(i+2) shl 16)
        require(String(bytes,0,4)=="RIFF"&&String(bytes,8,4)=="WAVE"&&word(20)==1&&word(22)==1&&word(34)==16&&String(bytes,36,4)=="data")
        val rate=int(24);val pcm=FloatArray((bytes.size-44)/2){word(44+it*2).toShort()/32768f}
        val samples=FloatArray((pcm.size.toLong()*16000/rate).toInt()){i->val x=i.toDouble()*rate/16000;val a=x.toInt().coerceAtMost(pcm.lastIndex);val b=(a+1).coerceAtMost(pcm.lastIndex);(pcm[a]*(1-(x-a))+pcm[b]*(x-a)).toFloat()}
        val started=SystemClock.elapsedRealtime()
        val transcript=store.acquire(id).use{OfflineMedia().use{it.transcribe(model.path,samples,"en")}}
        val text=transcript.text.lowercase()
        for(word in listOf("not","cancel","order","train"))assertTrue("Missing '$word': ${transcript.text}",text.contains(word))
        assertEquals("en",transcript.language)
        report("MEDIA_ASR id=$id seconds=${(SystemClock.elapsedRealtime()-started)/1000.0} text=${transcript.text}")
    }
    @Test fun ocr(){
        val detector=path("ppocr-v5-det");val recognizer=path("ppocr-v5-english")
        val bitmap=Bitmap.createBitmap(900,300,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(bitmap);canvas.drawColor(Color.WHITE)
        canvas.drawText("HELLO WORLD",50f,160f,Paint(Paint.ANTI_ALIAS_FLAG).apply{color=Color.BLACK;textSize=68f})
        val array=JSONArray(context.assets.open("ocr-english-characters.json").bufferedReader().use{it.readText()})
        val dictionary=List(array.length()){array.getString(it)}
        try{
            val blocks=store.acquire("ppocr-v5-det").use{store.acquire("ppocr-v5-english").use{OfflineMedia().use{it.recognize(bitmap,detector.path,recognizer.path,dictionary)}}}
            val text=blocks.joinToString(" "){it.text}
            assertTrue("Expected HELLO WORLD; actual=$text",text.uppercase().contains("HELLO")&&text.uppercase().contains("WORLD"))
            assertTrue(blocks.all{it.left in 0f..1f&&it.top in 0f..1f&&it.right>it.left&&it.bottom>it.top})
            report("MEDIA_OCR blocks=${blocks.size} text=$text")
        }finally{bitmap.recycle()}
    }
}
