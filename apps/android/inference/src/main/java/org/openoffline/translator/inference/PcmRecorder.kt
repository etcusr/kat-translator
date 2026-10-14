package org.openoffline.translator.inference

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/** Foreground-only mono recording. Request RECORD_AUDIO permission before start. */
class PcmRecorder(private val vadModelPath: String? = null) : AutoCloseable {
    @Volatile var speechDetected = false; private set
    @Volatile var lastSpeechMillis = 0L; private set
    @Volatile var isRecording = false; private set
    @Volatile var isPaused = false; private set
    @Volatile var rms = 0f; private set
    @Volatile var elapsedMillis = 0L; private set
    @Volatile var failure: String? = null; private set
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    private class PcmBuffer : ByteArrayOutputStream() {
        fun samples(start:Int,end:Int):FloatArray {
            require(start>=0 && end>=start && end<=count/2){"Invalid recorded sample range"}
            return FloatArray(end-start){i->val offset=2*(start+i);(((buf[offset].toInt() and 255) or (buf[offset+1].toInt() shl 8)).toShort().toInt()/32768f)}
        }
    }
    private var output = PcmBuffer()
    private var lastSamples = FloatArray(0)
    private val running = AtomicBoolean(false)
    private val sampleLock = Any()
    @SuppressLint("MissingPermission")
    @Synchronized fun start() {
        check(!isRecording) { "Already recording" }
        // A limit/read-error may have ended the worker before the UI collected it.
        if(recorder!=null)stop()
        val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "16 kHz mono recording is unavailable" }
        val record = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,maxOf(minimum*2,4096))
        if(record.state != AudioRecord.STATE_INITIALIZED) { record.release(); error("Microphone initialization failed") }
        speechDetected=false;lastSpeechMillis=0
        synchronized(sampleLock){output = PcmBuffer()};lastSamples=FloatArray(0);failure=null;elapsedMillis=0;isPaused=false;rms=0f
        try { record.startRecording() } catch(e:Exception) { record.release();throw e }
        recorder=record;running.set(true);isRecording=true
        worker=Thread({
            val buffer=ShortArray(512)
            var vad=0L
            try {
                if(vadModelPath!=null){vad=MediaNative.vadCreate(vadModelPath.toByteArray(Charsets.UTF_8));check(vad!=0L){"Silero VAD could not be loaded"}}
                while(running.get()) {
                    val n=record.read(buffer,0,buffer.size,AudioRecord.READ_BLOCKING)
                    if(n<0) { if(running.get()) error("Microphone read failed ($n)");break }
                    if(n==0||isPaused)continue
                    synchronized(sampleLock) {
                        if(isPaused)return@synchronized
                        var energy=0.0
                        for(i in 0 until n){val v=buffer[i].toInt();output.write(v and 255);output.write((v shr 8) and 255);energy += (v/32768.0)*(v/32768.0)}
                        rms=sqrt(energy/n).toFloat();elapsedMillis=output.size()/32L
                        if(vad!=0L && MediaNative.vadAccept(vad,FloatArray(n){buffer[it]/32768f})){speechDetected=true;lastSpeechMillis=elapsedMillis}
                        if(elapsedMillis>=30*60*1000L)running.set(false)
                    }
                }
            } catch(e:Exception){failure=e.message ?: "Recording failed";running.set(false)}
            finally { if(vad!=0L)MediaNative.vadFree(vad);try{record.stop()}catch(_:IllegalStateException){};isRecording=false;rms=0f }
        },"kat-audio-record").also{it.start()}
    }
    fun pause(){synchronized(sampleLock){isPaused=true;rms=0f}}
    fun resume(){synchronized(sampleLock){isPaused=false}}
    /** Captured audio so far; pauses were never added to the buffer. */
    val sampleCount:Int get()=synchronized(sampleLock){output.size()/2}
    fun snapshot():FloatArray=synchronized(sampleLock){output.samples(0,output.size()/2)}
    /** Copies only the selected <=30-second segment, never the full recording. */
    fun snapshot(startSample:Int,endSample:Int):FloatArray=synchronized(sampleLock){
        require(endSample.toLong()-startSample<=16000L*30){"Preview segment exceeds 30 seconds"}
        output.samples(startSample,endSample)
    }
    @Synchronized fun stop():FloatArray {
        val record=recorder ?: return lastSamples
        running.set(false)
        try{record.stop()}catch(_:IllegalStateException){}
        worker?.join();worker=null;record.release();recorder=null;isRecording=false;isPaused=false;rms=0f
        val bytes=synchronized(sampleLock){output.toByteArray().also{output.reset()}}
        lastSamples=FloatArray(bytes.size/2){i->(((bytes[2*i].toInt() and 255) or (bytes[2*i+1].toInt() shl 8)).toShort().toInt()/32768f)}
        return lastSamples
    }
    override fun close(){stop()}
}
