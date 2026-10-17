package org.openoffline.translator.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.openoffline.translator.inference.Transcript
import java.io.Closeable
import java.io.File
import java.util.Locale
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** On-device service only. Call transcribe on a worker while the app is foreground.
 * Input is mono Float PCM at 16 kHz. No microphone capture, downloads or network fallback.
 * FILE uses fast input for short clips; longer recordings must be paced: Pixel otherwise
 * reports successful completion after only the first utterance. App-owned ASR avoids this limit.
 * Preparation binds a service and checks offline support; each transcription consumes and destroys
 * that service, so cancellation does not poison subsequent calls. Android owns model residency. */
class SystemSpeechRecognizer(
    context: Context,
    private val inputMode: InputMode = InputMode.FILE,
    private val timeoutMillis: Long = 45_000,
    private val trace: (String) -> Unit = {},
) : Closeable {
    enum class InputMode { FILE, PACED_PIPE }
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val active = AtomicReference<Session?>()
    private val cancellationGeneration = AtomicLong()
    private var preparedRecognizer:SpeechRecognizer?=null // main thread only; OS owns its model memory
    private var preparedLanguage:String?=null
    private var preparedAuto=false

    fun releasePrepared() { main.post { preparedRecognizer?.destroy();preparedRecognizer=null;preparedLanguage=null } }

    /** Bind the selected on-device service and verify installed language support before recording.
     * Android does not expose control over when the service maps its own model weights. */
    @SuppressLint("NewApi")
    fun prepare(source:String,isCancelled:()->Boolean) {
        check(Looper.myLooper()!=Looper.getMainLooper())
        check(Build.VERSION.SDK_INT>=33 && !closed.get())
        val auto=source.isBlank() || source=="auto"
        check(!auto || Build.VERSION.SDK_INT>=34)
        val language=when(source) { "en" -> "en-US";"ru" -> "ru-RU";else -> if(auto)"en-US" else Locale.forLanguageTag(source).toLanguageTag() }
        val generation=cancellationGeneration.get()
        val done=CountDownLatch(1);val failure=AtomicReference<Exception?>()
        var service:SpeechRecognizer?=null
        fun cancelled()=closed.get() || isCancelled() || generation!=cancellationGeneration.get()
        main.post {
            try {
                if(cancelled())throw CancellationException()
                preparedRecognizer?.destroy();preparedRecognizer=null;preparedLanguage=null
                check(SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) { "No on-device speech recognition service is installed" }
                val created=SpeechRecognizer.createOnDeviceSpeechRecognizer(context);service=created
                val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE,language)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true)
                }
                created.checkRecognitionSupport(intent,context.mainExecutor,object:RecognitionSupportCallback {
                    override fun onSupportResult(support:RecognitionSupport) {
                        try {
                            if(cancelled())throw CancellationException()
                            val installed=support.installedOnDeviceLanguages
                            val required=if(auto)listOf("en-US","ru-RU") else listOf(language)
                            check(required.all { wanted -> installed.any { it.equals(wanted,true) } }) { "Offline speech language is not installed" }
                            preparedRecognizer=created;preparedLanguage=language;preparedAuto=auto
                        } catch(e:Exception) { failure.set(e);created.destroy() }
                        finally { done.countDown() }
                    }
                    override fun onError(error:Int) { failure.set(IllegalStateException("Offline recognition preparation failed ($error)"));created.destroy();done.countDown() }
                })
            } catch(e:Exception) { failure.set(e);done.countDown() }
        }
        val deadline=SystemClock.elapsedRealtime()+timeoutMillis
        try {
            while(!done.await(40,TimeUnit.MILLISECONDS)) {
                if(cancelled())throw CancellationException()
                if(SystemClock.elapsedRealtime()>=deadline)throw TimeoutException("Offline recognition preparation timed out")
            }
            if(cancelled())throw CancellationException()
            failure.get()?.let { throw it }
        } catch(e:Exception) {
            // Main owns both service creation and destruction, including a late support callback.
            cancellationGeneration.incrementAndGet()
            main.post { service?.destroy();if(preparedRecognizer===service) { preparedRecognizer=null;preparedLanguage=null } }
            throw e
        }
    }

    fun cancel() {
        cancellationGeneration.incrementAndGet()
        active.get()?.abort(CancellationException("Speech recognition cancelled"));releasePrepared()
    }
    override fun close() { closed.set(true);cancel() }

    fun transcribe(samples: FloatArray, source: String, isCancelled: () -> Boolean): Transcript {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Speech recognition must run on a worker" }
        check(Build.VERSION.SDK_INT >= 33) { "Offline recognition of recorded audio requires Android 13 or later" }
        check(!closed.get()) { "Speech recognizer is closed" }
        require(samples.isNotEmpty()) { "Recording is empty" }
        require(timeoutMillis in 1_000..600_000)
        val auto = source.isBlank() || source == "auto"
        check(!auto || Build.VERSION.SDK_INT >= 34) { "Automatic offline language detection requires Android 14 or later" }
        val tag = when(source) { "en" -> "en-US"; "ru" -> "ru-RU"; else -> Locale.forLanguageTag(source).toLanguageTag() }
        val generation = cancellationGeneration.get()
        var session = Session(auto, if(auto) "en-US" else tag)
        check(active.compareAndSet(null, session)) { "Speech recognition is already running" }
        val deadline = SystemClock.elapsedRealtime() + maxOf(timeoutMillis,samples.size*1000L/16000+15_000)
        fun guard() {
            if(closed.get() || isCancelled() || cancellationGeneration.get() != generation)
                throw CancellationException("Speech recognition cancelled")
            if(SystemClock.elapsedRealtime() >= deadline) throw TimeoutException("Offline speech recognition timed out")
        }
        fun runSession(current: Session, audio:FloatArray=samples): Transcript {
            try {
                guard()
                current.prepare(audio, ::guard)
                main.post { current.start() }
                while(!current.done.await(40, TimeUnit.MILLISECONDS)) guard()
                guard()
                current.failure?.let { throw it }
                return requireNotNull(current.result) { "Offline recognizer returned no transcript" }
            } catch(error: Exception) {
                current.abort(error)
                throw error
            } finally { current.dispose() }
        }
        try {
            if(!auto)return runSession(session)
            val detected = runSession(session)
            // Language switching can drop audio before its decision (Pixel RU loses the greeting).
            // Replay the identical full recording with the detected language, even when it matches
            // the initial hint: automatic switching may have switched away and back internally.
            guard()
            val detectedTag = when(detected.language) {
                "en" -> "en-US"
                "ru" -> "ru-RU"
                else -> error("Offline recognizer identified an unsupported recording language")
            }
            session = Session(false, detectedTag)
            active.set(session) // Preserve the operation lock across both passes.
            // The generation check also catches cancellation in the inter-session handoff.
            return runSession(session)
        } finally { active.compareAndSet(session, null) }
    }

    // Constructed only after transcribe checks API 33; auto is gated at API 34.
    @SuppressLint("NewApi")
    private inner class Session(val auto: Boolean, val language: String) {
        val done = CountDownLatch(1)
        val cancelled = AtomicBoolean(false)
        @Volatile var failure: Exception? = null
        @Volatile var result: Transcript? = null
        private var recognizer: SpeechRecognizer? = null // main thread only
        private var completed = false // main thread only
        private var file: File? = null
        private var input: ParcelFileDescriptor? = null
        private var output: ParcelFileDescriptor? = null
        private var writer: Thread? = null
        private val segments = mutableListOf<String>()
        private var detected: String? = null
        private var pcm: FloatArray? = null

        fun prepare(samples: FloatArray, guard: () -> Unit) {
            if(inputMode == InputMode.PACED_PIPE || samples.size>8*16000) {
                val pipe = ParcelFileDescriptor.createPipe();input=pipe[0];output=pipe[1];pcm=samples
            } else {
                file=File.createTempFile("offline-speech-", ".pcm", context.cacheDir)
                file!!.outputStream().buffered().use { stream ->
                    for(start in samples.indices step 1600) { guard();stream.write(encode(samples,start,minOf(start+1600,samples.size))) }
                }
                input=ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)
            }
        }
        fun abort(error: Exception) {
            cancelled.set(true)
            // Closing the pipe wakes a blocked writer. Service lifecycle calls remain on main.
            runCatching { output?.close() }
            main.post { finish(null,error) }
        }
        fun dispose() {
            cancelled.set(true)
            runCatching { output?.close() };writer?.interrupt()
            main.post {
                if(!completed) finish(null,CancellationException("Speech recognition closed"))
                runCatching { input?.close() };file?.delete()
            }
        }
        fun start() {
            if(cancelled.get() || completed) { finish(null,CancellationException("Speech recognition cancelled"));return }
            try {
                check(SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) { "No on-device speech recognition service is installed" }
                val service=if(preparedRecognizer!=null && preparedLanguage==language && preparedAuto==auto) {
                    requireNotNull(preparedRecognizer).also { preparedRecognizer=null;preparedLanguage=null }
                } else SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                recognizer=service
                service.setRecognitionListener(listener)
                val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE,language)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,false)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE,input)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT,1)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,AudioFormat.ENCODING_PCM_16BIT)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE,16000)
                    putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION,RecognizerIntent.EXTRA_AUDIO_SOURCE)
                    if(auto) {
                        putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION,true)
                        putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH,RecognizerIntent.LANGUAGE_SWITCH_BALANCED)
                        putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,arrayListOf("en-US","ru-RU"))
                        putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES,arrayListOf("en-US","ru-RU"))
                    }
                }
                service.checkRecognitionSupport(intent,context.mainExecutor,object:RecognitionSupportCallback {
                    override fun onSupportResult(support:RecognitionSupport) {
                        if(completed || cancelled.get())return
                        try {
                            val installed=support.installedOnDeviceLanguages.map { Locale.forLanguageTag(it).toLanguageTag() }
                            val required=if(auto)listOf("en-US","ru-RU") else listOf(language)
                            check(required.all { wanted -> installed.any { it.equals(wanted,true) } }) {
                                "Offline language ${required.joinToString()} is not installed for recorded-audio recognition (installed: ${installed.joinToString()})"
                            }
                            service.startListening(intent)
                            if(pcm != null) startWriter()
                        } catch(error:Exception) { finish(null,error) }
                    }
                    override fun onError(error:Int) { finish(null,recognitionError("support check",error)) }
                })
            } catch(error:Exception) { finish(null,error) }
        }
        private fun startWriter() {
            writer=Thread({
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(requireNotNull(output)).use { stream ->
                        val samples=requireNotNull(pcm)
                        val startTime=SystemClock.elapsedRealtime()
                        for(start in samples.indices step 320) {
                            if(cancelled.get())return@Thread
                            stream.write(encode(samples,start,minOf(start+320,samples.size)))
                            val wait=startTime+(start+320)*1000L/16000-SystemClock.elapsedRealtime()
                            if(wait>0)Thread.sleep(wait)
                        }
                    } // EOF ends the segmented session; never stopListening early.
                } catch(error:Exception) { if(!cancelled.get())main.post { finish(null,error) } }
                finally { pcm=null }
            },"offline-speech-pcm").apply { isDaemon=true;start() }
        }
        private fun finish(value:Transcript?, error:Exception?) {
            if(completed)return
            completed=true;result=value;failure=error
            runCatching { recognizer?.cancel() };runCatching { recognizer?.destroy() };recognizer=null
            runCatching { output?.close() };writer?.interrupt()
            done.countDown()
        }
        private fun complete(finalText:String?=null) {
            val text=if(segments.isNotEmpty())segments.joinToString(" ") else finalText.orEmpty()
            val selected=if(auto)detected else Locale.forLanguageTag(language).language
            when {
                text.isBlank() -> finish(null,IllegalStateException("Offline recognizer returned no speech"))
                selected.isNullOrBlank() -> finish(null,IllegalStateException("Offline recognizer did not confidently identify the recording language"))
                else -> finish(Transcript(text,selected),null)
            }
        }
        private fun event(name:String,bundle:Bundle?=null) {
            val position=runCatching { android.system.Os.lseek(requireNotNull(input).fileDescriptor,0,android.system.OsConstants.SEEK_CUR) }.getOrDefault(-1)
            trace("$name chars=${text(bundle).length} segments=${segments.size} readBytes=$position totalBytes=${file?.length() ?: -1}")
        }
        private fun text(bundle:Bundle?)=bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty()
        private val listener=object:RecognitionListener {
            override fun onReadyForSpeech(params:Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB:Float) {}
            override fun onBufferReceived(buffer:ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onError(error:Int) { event("error=$error");finish(null,recognitionError("recognition",error)) }
            override fun onResults(results:Bundle?) { event("results",results);complete(text(results)) }
            override fun onPartialResults(partialResults:Bundle?) {}
            override fun onEvent(eventType:Int,params:Bundle?) {}
            override fun onSegmentResults(segmentResults:Bundle) { event("segment",segmentResults);if(!completed)text(segmentResults).takeIf { it.isNotBlank() }?.let { segments+=it } }
            override fun onEndOfSegmentedSession() { event("segmentedEnd");complete() }
            override fun onLanguageDetection(results:Bundle) {
                if(!auto || completed)return
                val confidence=results.getInt(SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL)
                val code=results.getString(SpeechRecognizer.DETECTED_LANGUAGE)?.let { Locale.forLanguageTag(it).language }
                if(confidence>=SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL_CONFIDENT && code in listOf("en","ru"))detected=code
            }
        }
    }
    private fun encode(samples:FloatArray,start:Int,end:Int):ByteArray {
        val bytes=ByteArray((end-start)*2)
        for(i in start until end) {
            require(samples[i].isFinite()) { "Recording contains invalid audio samples" }
            val value=(samples[i].coerceIn(-1f,1f)*32767f).toInt()
            bytes[(i-start)*2]=value.toByte();bytes[(i-start)*2+1]=(value shr 8).toByte()
        }
        return bytes
    }
    private fun recognitionError(stage:String,code:Int)=IllegalStateException("On-device speech $stage failed: "+when(code) {
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "offline language is not installed"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language is not supported"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "microphone permission or foreground access is missing"
        SpeechRecognizer.ERROR_NO_MATCH -> "no speech could be recognized"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no speech detected"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "service is busy"
        SpeechRecognizer.ERROR_AUDIO -> "service cannot read supplied audio"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "service cannot verify offline support for supplied audio"
        else -> "service error $code"
    }+" (code $code)")
}
