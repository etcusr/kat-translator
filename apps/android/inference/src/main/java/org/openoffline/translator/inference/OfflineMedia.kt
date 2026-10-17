package org.openoffline.translator.inference

import android.graphics.Bitmap
import java.io.File
import java.util.concurrent.CancellationException
import kotlin.math.*

internal object MediaNative {
    init { System.loadLibrary("kat_whisper"); System.loadLibrary("kat_media") }
    external fun whisperArm82Supported():Boolean
    external fun whisperI8mmSupported():Boolean
    val acceleratedWhisper:Boolean by lazy {
        if(!whisperArm82Supported()) false else try {
            System.loadLibrary("kat_whisper_arm82");true
        } catch(_:UnsatisfiedLinkError) { false }
    }
    // Separate JNI names allow Q8 to use i8mm while other models keep their original backend.
    val i8mmWhisper:Boolean by lazy {
        if(!whisperI8mmSupported()) false else try {
            System.loadLibrary("kat_whisper_i8mm");true
        } catch(_:UnsatisfiedLinkError) { false }
    }
    external fun whisperI8mm(path:ByteArray,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperI8mmCreate(path:ByteArray):Long
    external fun whisperI8mmRun(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperI8mmWordsRun(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperI8mmFree(handle:Long)
    external fun whisperArm82(path:ByteArray,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperCreate(path:ByteArray):Long
    external fun whisperRun(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperWordsRun(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperFree(handle:Long)
    external fun whisperArm82Create(path:ByteArray):Long
    external fun whisperArm82Run(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperArm82WordsRun(handle:Long,samples:FloatArray,language:ByteArray,flag:Long):ByteArray?
    external fun whisperArm82Free(handle:Long)
    external fun piperCreate(model:ByteArray,tokens:ByteArray,data:ByteArray):Long
    external fun piperFree(handle:Long)
    external fun piperRun(handle:Long,text:ByteArray,flag:Long,rate:IntArray,timing:DoubleArray,callback:SpeechChunkCallback?):FloatArray?
    external fun vadCreate(path: ByteArray): Long
    external fun vadAccept(handle: Long, samples: FloatArray): Boolean
    external fun vadFree(handle: Long)
    external fun flagCreate(): Long
    external fun flagCancel(flag: Long)
    external fun flagFree(flag: Long)
    external fun whisper(path: ByteArray, samples: FloatArray, language: ByteArray, flag: Long): ByteArray?
    external fun wayu(runtime: ByteArray, directory: ByteArray, text: ByteArray, voice: ByteArray, flag: Long): FloatArray?
    external fun wayuTokens(runtime: ByteArray, text: ByteArray): LongArray
    external fun omniVoice(directory: ByteArray, text: ByteArray, language: ByteArray, flag: Long): FloatArray?
    external fun nemoCreate(directory:ByteArray,parakeet:Boolean):Long
    external fun nemoFree(handle:Long)
    external fun nemoRun(handle:Long,samples:FloatArray,flag:Long):ByteArray?
    external fun omniCreate(path:ByteArray,tokens:ByteArray):Long
    external fun omniFree(handle:Long)
    external fun omniRun(handle:Long,samples:FloatArray,flag:Long):ByteArray?
    external fun omni(path: ByteArray, tokens: ByteArray, samples: FloatArray, flag: Long): ByteArray?
    external fun tts(model: ByteArray, tokens: ByteArray, data: ByteArray, text: ByteArray, language: ByteArray, supertonic: Boolean, flag: Long, rate: IntArray, timing: DoubleArray): FloatArray?
    external fun ocrLoad(path: ByteArray): Long
    external fun ocrFree(handle: Long)
    external fun ocrHeight(handle: Long): Int
    external fun ocrRun(handle: Long, input: FloatArray, width: Int): IntArray
    external fun ocrRunScored(handle: Long, input: FloatArray, width: Int): FloatArray
    external fun detect(path: ByteArray, input: FloatArray, width: Int, height: Int): FloatArray
}
/** Native calls synchronously on the synthesis thread; consumers must not retain native buffers. */
fun interface SpeechChunkCallback { fun onChunk(samples:FloatArray,sampleRate:Int) }
data class Transcript(val text: String, val language: String)
/** Wall-clock phases of the last native Piper/Supertonic call; contains no text or audio. */
data class SpeechSynthesisTiming(val load:Double,val generate:Double,val copy:Double,val release:Double)
data class SpeechAudio(val samples: FloatArray, val sampleRate: Int) {
    init { require(sampleRate in 8000..192000); require(samples.isNotEmpty() && samples.all { it.isFinite() }) }
}
data class OcrRecognizer(val modelId: String, val path: String, val dictionary: List<String>)
data class OcrBlock(val text: String, val left: Float, val top: Float, val right: Float, val bottom: Float)

/** Blocking offline operations. A caller must schedule these away from the UI thread and unload
 * translation as required by the caller. The selected Whisper/GigaAM/Parakeet/Omnilingual recognizer
 * can be prepared before capture and is retained until releaseRecognition/close. Piper retains one
 * voice until explicit unload/memory pressure/close; other operations own their model.
 * cancel is safe from another thread; close waits for the current native call to return. */
class OfflineMedia : AutoCloseable {
    @Volatile var lastSpeechTiming:SpeechSynthesisTiming?=null;private set
    private val flagLock = Any()
    private var flag = 0L
    @Volatile private var cancelled = false
    private var closed = false
    private fun utf8(s: String): ByteArray { require('\u0000' !in s); return s.toByteArray(Charsets.UTF_8) }
    private fun file(path: String): ByteArray { require(File(path).isFile) { "Install the offline model first: ${File(path).name}" }; return utf8(path) }
    private inline fun <T> operation(isCancelled: () -> Boolean = { false }, action: (Long) -> T): T {
        check(!closed) { "Media engine closed" }
        val current = synchronized(flagLock) {
            if(isCancelled())throw CancellationException("Media operation cancelled before start")
            cancelled = false; MediaNative.flagCreate().also { check(it != 0L); flag = it }
        }
        try { return action(current).also { checkCancellation() } }
        finally { synchronized(flagLock) { flag = 0; MediaNative.flagFree(current) } }
    }
    private fun checkCancellation() { if (cancelled || Thread.currentThread().isInterrupted) throw CancellationException("Media operation cancelled") }
    fun cancel() = synchronized(flagLock) { cancelled = true; if (flag != 0L) MediaNative.flagCancel(flag) }
    private val whisperCache=WhisperModelCache { backend,handle ->
        when(backend) {
            WhisperBackend.I8MM -> MediaNative.whisperI8mmFree(handle)
            WhisperBackend.ARM82 -> MediaNative.whisperArm82Free(handle)
            WhisperBackend.BASELINE -> MediaNative.whisperFree(handle)
        }
    }
    private val piperCache=NativeModelCache { MediaNative.piperFree(it) }
    private val omniCache=NativeModelCache { MediaNative.omniFree(it) }
    private var omniLoaded=false
    private var nemoLoads=0
    private var nemoFamily:String?=null
    val recognitionLoads get()=whisperCache.loads+nemoLoads+omniCache.loads
    val recognitionRuntime get()=whisperCache.backend?.name?.lowercase() ?: nemoFamily ?: if(omniLoaded)"omnilingual" else null
    val voiceLoads get()=piperCache.loads
    private fun identity(vararg paths:String)=paths.joinToString("|") { path ->
        val f=File(path);"${f.canonicalPath}:${f.length()}:${f.lastModified()}"
    }
    @Synchronized fun releaseSpeech() { piperCache.close() }
    @Synchronized fun releaseModels() { releaseRecognition();releaseSpeech() }
    @Synchronized fun preloadPiper(model:String,tokens:String,dataDir:String) {
        check(!closed);val m=file(model);val t=file(tokens);val d=utf8(dataDir)
        piperCache.acquire(identity(model,tokens,dataDir)) { MediaNative.piperCreate(m,t,d) }
    }
    private var nemoHandle=0L
    private var nemoKey=""
    @Synchronized fun releaseRecognition() {
        whisperCache.close();omniCache.close();omniLoaded=false;nemoFamily=null
        if(nemoHandle!=0L)MediaNative.nemoFree(nemoHandle)
        nemoHandle=0;nemoKey=""
    }
    @Synchronized override fun close() { closed = true;releaseModels() }
    @Synchronized fun preloadWhisper(modelPath:String,isCancelled:()->Boolean={false}) = operation(isCancelled) {
        ensureWhisper(modelPath);checkCancellation();if(isCancelled())throw CancellationException()
    }
    @Synchronized fun preloadNemo(directory:String,parakeet:Boolean,isCancelled:()->Boolean={false}) = operation(isCancelled) {
        fun guard() { checkCancellation();if(isCancelled())throw CancellationException() }
        ensureNemo(directory,parakeet,::guard);guard()
    }
    @Synchronized fun preloadOmnilingual(modelPath:String,tokensPath:String,isCancelled:()->Boolean={false}) = operation(isCancelled) {
        ensureOmnilingual(modelPath,tokensPath);checkCancellation();if(isCancelled())throw CancellationException()
    }
    private fun ensureNemo(directory:String,parakeet:Boolean,guard:()->Unit) {
        val files=listOf("encoder.int8.onnx",if(parakeet)"decoder.int8.onnx" else "decoder.onnx",if(parakeet)"joiner.int8.onnx" else "joiner.onnx","tokens.txt").map { File(directory,it) }
        files.forEach { file(it.path) }
        val key=files.joinToString { "${it.canonicalPath}:${it.length()}:${it.lastModified()}" }
        if(key!=nemoKey || nemoHandle==0L) {
            releaseRecognition();guard()
            nemoHandle=MediaNative.nemoCreate(utf8(directory),parakeet);check(nemoHandle!=0L);nemoKey=key
            nemoFamily=if(parakeet)"parakeet" else "gigaam";nemoLoads++
        }
    }
    private fun ensureWhisper(modelPath:String):Pair<WhisperBackend,Long> {
        val path=file(modelPath)
        if(nemoHandle!=0L || omniLoaded)releaseRecognition()
        val name=File(modelPath).name
        val backend=whisperBackendFor(name,MediaNative.acceleratedWhisper,
            name=="ggml-large-v3-turbo-q8_0.bin" && MediaNative.acceleratedWhisper && MediaNative.i8mmWhisper)
        val handle=whisperCache.acquire(identity(modelPath),backend) {
            when(it) {
                WhisperBackend.I8MM -> MediaNative.whisperI8mmCreate(path)
                WhisperBackend.ARM82 -> MediaNative.whisperArm82Create(path)
                WhisperBackend.BASELINE -> MediaNative.whisperCreate(path)
            }
        }
        return backend to handle
    }
    private fun ensureOmnilingual(modelPath:String,tokensPath:String):Long {
        val model=file(modelPath);val tokens=file(tokensPath)
        if(nemoHandle!=0L || whisperCache.backend!=null)releaseRecognition()
        return try { omniCache.acquire(identity(modelPath,tokensPath)) { MediaNative.omniCreate(model,tokens) }.also { omniLoaded=true } }
        catch(e:Exception) { omniLoaded=false;throw e }
    }
    fun transcribeGigaAM(directory:String,samples:FloatArray,vadPath:String,isCancelled:()->Boolean={false}):Transcript =
        transcribeNemo(directory,samples,vadPath,"ru",false,isCancelled)
    fun transcribeParakeet(directory:String,samples:FloatArray,vadPath:String,language:String,isCancelled:()->Boolean={false}):Transcript =
        transcribeNemo(directory,samples,vadPath,language,true,isCancelled)
    @Synchronized private fun transcribeNemo(directory:String,samples:FloatArray,vadPath:String,language:String,parakeet:Boolean,isCancelled:()->Boolean):Transcript = operation(isCancelled) { f ->
        require(language.isNotBlank() && language!="auto") { "Select the speech language" }
        validatePcm(samples)
        fun guard() { checkCancellation();if(isCancelled())throw CancellationException("Speech recognition cancelled") }
        ensureNemo(directory,parakeet,::guard)
        guard()
        val parts=RecordedSpeechSegments.detect(samples,vadPath,::guard)
        var text=""
        for(part in parts) {
            guard()
            val raw=MediaNative.nemoRun(nemoHandle,if(parts.size==1)samples else samples.copyOfRange(part.start,part.end),f) ?: throw CancellationException()
            guard();text=RecordedSpeechSegments.append(text,String(raw,Charsets.UTF_8),part.overlapsPrevious)
        }
        check(text.isNotBlank()) { "No speech detected" }
        Transcript(text,language)
    }
    @Synchronized fun transcribe(modelPath: String, samples: FloatArray, language: String = "auto", whisperDateTimeRepair: Boolean = false, isCancelled: () -> Boolean = { false }): Transcript = operation(isCancelled) { f ->
        validatePcm(samples)
        val lang=utf8(language)
        val (backend,handle)=ensureWhisper(modelPath)
        checkCancellation();if(isCancelled())throw CancellationException()
        val raw = when(backend) {
            WhisperBackend.I8MM -> MediaNative.whisperI8mmRun(handle,samples,lang,f)
            WhisperBackend.ARM82 -> MediaNative.whisperArm82Run(handle,samples,lang,f)
            WhisperBackend.BASELINE -> MediaNative.whisperRun(handle,samples,lang,f)
        } ?: throw CancellationException()
        checkCancellation();if(isCancelled())throw CancellationException()
        val output = String(raw, Charsets.UTF_8); val split = output.indexOf('\n')
        check(split > 0) { "Invalid Whisper result" }
        val text = output.substring(split + 1).trim(); check(text.isNotEmpty()) { "No speech detected" }
        val detected = output.substring(0, split)
        val repaired = WhisperDateTimeRepair.apply(text, detected, samples.size, whisperDateTimeRepair,
            { cancelled || isCancelled() }) {
            val retryLanguage = utf8("ru")
            val retry = when(backend) {
                WhisperBackend.I8MM -> MediaNative.whisperI8mmWordsRun(handle,samples,retryLanguage,f)
                WhisperBackend.ARM82 -> MediaNative.whisperArm82WordsRun(handle,samples,retryLanguage,f)
                WhisperBackend.BASELINE -> MediaNative.whisperWordsRun(handle,samples,retryLanguage,f)
            } ?: throw CancellationException()
            val retryOutput = String(retry, Charsets.UTF_8)
            val retrySplit = retryOutput.indexOf('\n')
            check(retrySplit > 0) { "Invalid Whisper retry result" }
            retryOutput.substring(retrySplit + 1).trim()
        }
        Transcript(repaired, detected)
    }
    @Synchronized fun transcribeOmnilingual(modelPath: String, tokensPath: String, samples: FloatArray, language: String, isCancelled: () -> Boolean = { false }): Transcript = operation(isCancelled) { f ->
        validatePcm(samples)
        val handle=ensureOmnilingual(modelPath,tokensPath)
        checkCancellation();if(isCancelled())throw CancellationException()
        val raw = MediaNative.omniRun(handle,samples,f) ?: throw CancellationException()
        val text = String(raw, Charsets.UTF_8).trim(); check(text.isNotEmpty()) { "No speech detected" }; Transcript(text, language)
    }
    @Synchronized fun synthesizePiper(model: String, tokens: String, dataDir: String, text: String, callback:SpeechChunkCallback?=null): SpeechAudio = operation { f ->
        require(text.isNotBlank() && text.length <= 20000)
        val rate = IntArray(1);val timing=DoubleArray(4);lastSpeechTiming=null
        val started=System.nanoTime();preloadPiper(model,tokens,dataDir)
        val load=(System.nanoTime()-started)/1e9
        checkCancellation()
        val handle=piperCache.acquire(identity(model,tokens,dataDir)) { error("Voice cache missing") }
        val samples = MediaNative.piperRun(handle,utf8(text),f,rate,timing,callback) ?: throw CancellationException()
        timing[0]=load
        lastSpeechTiming=SpeechSynthesisTiming(timing[0],timing[1],timing[2],timing[3])
        SpeechAudio(samples, rate[0])
    }
    @Synchronized fun synthesizeSupertonic(directory: String, text: String, language: String): SpeechAudio = operation { f ->
        require(text.isNotBlank() && text.length <= 20000)
        require(File(directory, "tts.json").isFile) { "Install the Supertonic voice package" }
        val rate = IntArray(1);val timing=DoubleArray(4);lastSpeechTiming=null
        val samples = MediaNative.tts(utf8(directory), utf8(""), utf8(""), utf8(text), utf8(language), true, f, rate,timing) ?: throw CancellationException()
        lastSpeechTiming=SpeechSynthesisTiming(timing[0],timing[1],timing[2],timing[3])
        SpeechAudio(samples, rate[0])
    }
    @Synchronized fun synthesizeWayu(runtimeDirectory: String, directory: String, text: String, voice: String = "m_elderly_deep"): SpeechAudio = operation { f ->
        require(text.isNotBlank() && text.length <= 2000)
        require(voice in wayuVoices) { "Unknown Wayu voice" }
        file(File(directory,"wayu-prosody.bin").path);file(File(directory,"wayu-curves.bin").path)
        file(File(directory,"wayu-decoder.bin").path);file(File(directory,"wayu-styles.bin").path)
        SpeechAudio(MediaNative.wayu(utf8(runtimeDirectory),utf8(directory),utf8(text),utf8(voice),f) ?: throw CancellationException(),24000)
    }
    companion object {
        val wayuVoices = listOf("f_teen_bright","f_young_bright","f_young_clear","f_young_warm","f_mid_clear","f_mid_warm","f_elderly_soft","f_elderly_low","m_teen_bright","m_young_clear","m_mid_warm","m_elderly_deep")
    }
    @Synchronized fun synthesizeOmniVoice(directory: String, text: String, language: String): SpeechAudio = operation { f ->
        require(text.isNotBlank() && text.length <= 2000)
        file(File(directory, "omnivoice-base-Q8_0.gguf").path)
        file(File(directory, "omnivoice-tokenizer-Q8_0.gguf").path)
        System.loadLibrary("kat_omnivoice")
        SpeechAudio(MediaNative.omniVoice(utf8(directory),utf8(text),utf8(language),f) ?: throw CancellationException(),24000)
    }
    @Synchronized fun recognize(image: Bitmap, detectorPath: String, recognizerPath: String, dictionary: List<String>): List<OcrBlock> = operation { _ ->
        recognizeInternal(image, detectorPath, listOf(OcrRecognizer("explicit", recognizerPath, dictionary)), false)
    }
    /** Detect once and evaluate each installed official recognizer on exactly the same crops.
     * One installed model means limited coverage; the caller must disclose that limitation. */
    @Synchronized fun recognizeAuto(image: Bitmap, detectorPath: String, recognizers: List<OcrRecognizer>): List<OcrBlock> = operation { _ ->
        require(recognizers.isNotEmpty() && recognizers.size <= 2 && recognizers.all { it.modelId in OcrAutoSelection.requiredModels })
        require(recognizers.map { it.modelId }.distinct().size == recognizers.size)
        recognizeInternal(image, detectorPath, recognizers, true)
    }
    private fun recognizeInternal(image: Bitmap, detectorPath: String, recognizers: List<OcrRecognizer>, auto: Boolean): List<OcrBlock> {
        require(image.width > 0 && image.height > 0 && recognizers.all { it.dictionary.size >= 2 })
        val scale = min(1f, 960f / max(image.width, image.height))
        val w = max(32, (image.width * scale / 32).roundToInt() * 32)
        val h = max(32, (image.height * scale / 32).roundToInt() * 32)
        val resized = Bitmap.createScaledBitmap(image, w, h, true)
        val pixels = IntArray(w * h); resized.getPixels(pixels, 0, w, 0, 0, w, h)
        if (resized !== image) resized.recycle()
        val input = OcrDecoding.detectorInput(pixels)
        checkCancellation()
        val probability = MediaNative.detect(file(detectorPath), input, w, h)
        checkCancellation()
        val boxes = OcrDecoding.boxes(probability, w, h)
        if (boxes.isEmpty()) return emptyList()
        val candidates = List(boxes.size) { mutableListOf<OcrAutoSelection.Candidate>() }
        for (recognizer in recognizers) {
          checkCancellation()
          val handle = MediaNative.ocrLoad(file(recognizer.path)); check(handle != 0L) { "OCR recognizer could not be loaded" }
          try {
            val height = MediaNative.ocrHeight(handle)
            boxes.forEachIndexed { index, b ->
                checkCancellation()
                val left = (b[0] * image.width).toInt().coerceIn(0, image.width - 1)
                val top = (b[1] * image.height).toInt().coerceIn(0, image.height - 1)
                val right = ceil(b[2] * image.width).toInt().coerceIn(left + 1, image.width)
                val bottom = ceil(b[3] * image.height).toInt().coerceIn(top + 1, image.height)
                val crop = Bitmap.createBitmap(image, left, top, right - left, bottom - top)
                val scaledWidth = ceil(height.toDouble() * crop.width / crop.height).toInt().coerceIn(1,4096)
                val width = max(320, scaledWidth)
                val scaled = Bitmap.createScaledBitmap(crop, scaledWidth, height, true)
                val rgba = IntArray(scaledWidth * height); scaled.getPixels(rgba,0,scaledWidth,0,0,scaledWidth,height)
                val data = FloatArray(3 * height * width)
                for(y in 0 until height) for(x in 0 until scaledWidth) for(c in 0..2)
                    data[c*height*width+y*width+x] = ((rgba[y*scaledWidth+x] ushr (c*8)) and 255)/127.5f-1f
                if(scaled !== crop) scaled.recycle(); if(crop !== image) crop.recycle()
                val candidate = if (auto) OcrAutoSelection.decode(recognizer.modelId,
                    MediaNative.ocrRunScored(handle,data,width),recognizer.dictionary)
                else OcrAutoSelection.Candidate(recognizer.modelId,
                    OcrDecoding.ctc(MediaNative.ocrRun(handle,data,width),recognizer.dictionary),1f)
                candidates[index] += candidate
            }
          } finally { MediaNative.ocrFree(handle) }
        }
        checkCancellation()
        return OcrLayout.group(boxes.mapIndexedNotNull { index, b ->
            val candidate = if (auto) OcrAutoSelection.choose(candidates[index]) else candidates[index].single()
            candidate?.text?.takeIf { it.isNotBlank() }?.let { OcrBlock(it,b[0],b[1],b[2],b[3]) }
        })
    }
    private fun validatePcm(samples: FloatArray) {
        require(samples.isNotEmpty() && samples.size <= 16000*60*30 && samples.all { it.isFinite() }) { "Expected finite mono 16 kHz audio up to 30 minutes" }
        check(samples.any { abs(it) > .0001f }) { "No speech detected" }
    }
}

/** Pure decoder utilities kept independent of Android for JVM boundary tests. */
object OcrDecoding {
    /** PP-OCRv5 server detector's published inference.yml specifies BGR, not RGB. */
    fun detectorInput(argb: IntArray): FloatArray {
        val input=FloatArray(3*argb.size)
        val means=floatArrayOf(.485f,.456f,.406f);val deviations=floatArrayOf(.229f,.224f,.225f)
        for(i in argb.indices)for(c in 0..2)
            input[c*argb.size+i]=(((argb[i] ushr (c*8)) and 255)/255f-means[c])/deviations[c]
        return input
    }
    fun ctc(ids: IntArray, dictionary: List<String>): String {
        var previous = -1
        return buildString { for(id in ids) { require(id in dictionary.indices) { "OCR dictionary does not match model" }; if(id != 0 && id != previous) append(dictionary[id]); previous = id } }.trim()
    }
    /** DB probability connected components; padded horizontal bounding boxes in reading order.
     * Rotated/perspective text needs the user's rotate/crop step; no false geometry precision. */
    fun boxes(probability: FloatArray,width: Int,height: Int): List<FloatArray> {
        require(width > 0 && height > 0 && probability.size == width*height)
        val seen = BooleanArray(probability.size); val queue = IntArray(probability.size); val boxes = mutableListOf<FloatArray>()
        for(start in probability.indices) {
            if(seen[start] || probability[start] < .3f) continue
            var head=0;var tail=1;queue[0]=start;seen[start]=true
            var x0=width;var y0=height;var x1=0;var y1=0;var score=0.0
            while(head<tail) {
                val i=queue[head++];val x=i%width;val y=i/width;x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y);score+=probability[i]
                fun add(j:Int){if(!seen[j]&&probability[j]>=.3f){seen[j]=true;queue[tail++]=j}}
                if(x>0)add(i-1);if(x+1<width)add(i+1);if(y>0)add(i-width);if(y+1<height)add(i+width)
            }
            if(tail<8||score/tail<.6||x1-x0<3||y1-y0<2)continue
            val padding=max(2f,(y1-y0)*.4f)
            boxes += floatArrayOf(max(0f,(x0-padding)/width),max(0f,(y0-padding)/height),min(1f,(x1+padding+1)/width),min(1f,(y1+padding+1)/height))
            if(boxes.size>=256)break
        }
        return boxes.sortedWith(compareBy<FloatArray>{(it[1]*height/12).toInt()}.thenBy{it[0]})
    }
}
