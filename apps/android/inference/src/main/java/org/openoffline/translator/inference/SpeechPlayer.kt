package org.openoffline.translator.inference

import android.content.Context
import android.media.*
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Metrics describe frames handed to/drained by AudioTrack, not an acoustic recording. */
data class SpeechPlaybackMetrics(val written:Long,val played:Long,val firstWriteNanos:Long,val completed:Boolean,val underruns:Int,val drainUnderruns:Int,val failure:String?)

/** One AudioTrack and one producer queue per utterance; late callbacks cannot restart a stopped session. */
class SpeechPlayer(context:Context?=null):AutoCloseable {
    private val manager=context?.getSystemService(AudioManager::class.java)
    private class Playback(val player:AudioTrack,val focus:AudioFocusRequest?,val input:SpeechStream) {
        val released=AtomicBoolean(false)
        @Volatile var active=true
        @Volatile var paused=false
        @Volatile var written=0L
        @Volatile var played=0L
        @Volatile var firstWriteNanos=0L
        @Volatile var completed=false
        @Volatile var underruns=0
        @Volatile var drainUnderruns=0
        @Volatile var failure:String?=null
    }
    @Volatile private var playback:Playback?=null
    private var worker:Thread?=null
    @Volatile var appliedGain=1.0;private set
    val isPlaying get()=playback?.active==true
    val isPaused get()=playback?.paused==true
    val metrics get()=playback?.let { SpeechPlaybackMetrics(it.written,it.played,it.firstWriteNanos,it.completed,it.underruns,it.drainUnderruns,it.failure) }
    private fun release(value:Playback) = synchronized(value) {
        if(value.released.compareAndSet(false,true)) {
            try { value.player.pause();value.player.flush();value.player.stop() } catch(_:IllegalStateException) {}
            value.player.release();value.focus?.let { manager?.abandonAudioFocusRequest(it) }
        }
    }
    @Synchronized fun startStream(sampleRate:Int,speed:Float=1f):SpeechStream = startStreamImpl(sampleRate,speed,false)
    private fun startStreamImpl(sampleRate:Int,speed:Float,normalizeRecording:Boolean):SpeechStream {
        require(sampleRate in 8000..192000 && speed in .5f..2f);stop()
        val attributes=AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        var request:AudioFocusRequest?=null
        var player:AudioTrack?=null
        try {
            if(manager!=null) {
                request=AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes).setOnAudioFocusChangeListener { change ->
                    synchronized(this) { if(change<0 && playback?.focus===request)pause() }
                }.build()
                check(manager.requestAudioFocus(request)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "Audio focus unavailable" }
            }
            val minimum=AudioTrack.getMinBufferSize(sampleRate,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_FLOAT)
            check(minimum>0)
            val created=AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate).setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()).setBufferSizeInBytes(maxOf(minimum*4,16384)).setTransferMode(AudioTrack.MODE_STREAM).build()
            player=created;check(created.state==AudioTrack.STATE_INITIALIZED) { "Audio playback unavailable" }
            created.playbackParams=PlaybackParams().setSpeed(speed).setPitch(1f)
            created.pause() // setPlaybackParams can start an empty track; wait for the first PCM write.
            appliedGain=1.0
            val input=SpeechStream();val session=Playback(created,request,input);playback=session
            worker=Thread({
                try {
                    var started=false
                    while(!input.stopped.get()) {
                        val chunk=input.take() ?: break
                        // Recording replay has one complete chunk. Estimate gain on this worker,
                        // then normalize bounded windows without copying the whole recording.
                        val gain=if(normalizeRecording)SpeechLoudness.recordingGain(chunk,sampleRate) else null
                        appliedGain=gain ?: 1.0
                        val adjusted=if(gain!=null)FloatArray(2048) else null
                        var offset=0
                        while(!input.stopped.get() && offset<chunk.size) {
                            if(session.paused) { Thread.sleep(20);continue }
                            val length=minOf(2048,chunk.size-offset)
                            if(adjusted!=null)for(i in 0 until length)adjusted[i]=SpeechLoudness.adjusted(chunk[offset+i],gain!!)
                            val count=created.write(adjusted ?: chunk,if(adjusted==null)offset else 0,length,AudioTrack.WRITE_NON_BLOCKING)
                            check(count>=0) { "AudioTrack write failed: $count" }
                            if(count==0)Thread.sleep(5) else {
                                offset+=count;session.written+=count
                                if(!started)synchronized(session) {
                                    created.setStartThresholdInFrames(minOf(1024,count))
                                    if(!session.paused)created.play()
                                    started=true;session.firstWriteNanos=System.nanoTime()
                                }
                            }
                        }
                    }
                    // Exclude AudioTrack asking for more PCM after the complete utterance ended.
                    session.underruns=created.underrunCount
                    while(!input.stopped.get()) {
                        session.played=created.playbackHeadPosition.toLong() and 0xffffffffL
                        if(session.played>=session.written)break
                        Thread.sleep(10)
                    }
                    session.completed=!input.stopped.get() && session.written>0 && session.played==session.written
                    session.drainUnderruns=created.underrunCount-session.underruns
                } catch(_:InterruptedException) {} catch(e:Exception) { session.failure=e.message }
                finally { session.active=false;session.paused=false;release(session) }
            },"kat-speech-play").also { it.start() }
            return input
        } catch(t:Throwable) {
            player?.release();request?.let { manager?.abandonAudioFocusRequest(it) };throw t
        }
    }
    @Synchronized fun play(audio:SpeechAudio,speed:Float=1f,normalizeVolume:Boolean=false) {
        startStreamImpl(audio.sampleRate,speed,normalizeVolume).apply { offerValidated(audio.samples);finish() }
    }
    @Synchronized fun pause() { playback?.let { session -> synchronized(session) {
        if(!session.released.get()) { session.paused=true;session.player.pause() }
    } } }
    @Synchronized fun resume() { playback?.let { session -> synchronized(session) {
        if(!session.released.get()) { if(session.written>0)session.player.play();session.paused=false }
    } } }
    @Synchronized fun setSpeed(speed:Float) {
        require(speed in .5f..2f)
        playback?.let { session -> synchronized(session) {
            if(!session.released.get()) {
                session.player.playbackParams=PlaybackParams().setSpeed(speed).setPitch(1f)
                if(session.paused)session.player.pause()
            }
        } }
    }
    @Synchronized fun stop() {
        playback?.input?.stop();worker?.interrupt();worker?.join();worker=null
        playback?.let { it.active=false;it.paused=false;release(it) }
    }
    override fun close() { stop() }
    fun exportWav(file:File,audio:SpeechAudio,normalizeVolume:Boolean=false)=writeWav(file,audio,normalizeVolume)
    companion object {
        /** Standard PCM16 mono WAV; no re-synthesis and no model data is exported. */
        fun writeWav(file:File,audio:SpeechAudio,normalizeVolume:Boolean=false){
            // One gain for the complete recording; keep ASR PCM untouched and avoid a full output copy.
            val gain=if(normalizeVolume)SpeechLoudness.recordingGain(audio.samples,audio.sampleRate) else null
            require(audio.samples.size <= (Int.MAX_VALUE-44)/2)
            FileOutputStream(file).use{out->
                fun str(s:String){out.write(s.toByteArray(Charsets.US_ASCII))}
                fun word(n:Int){out.write(n and 255);out.write((n ushr 8) and 255)}
                fun int(n:Int){word(n and 65535);word(n ushr 16)}
                str("RIFF");int(36+audio.samples.size*2);str("WAVEfmt ");int(16);word(1);word(1);int(audio.sampleRate);int(audio.sampleRate*2);word(2);word(16);str("data");int(audio.samples.size*2)
                val buffer=ByteArray(8192);var offset=0
                for(v in audio.samples){val adjusted=if(gain!=null)SpeechLoudness.adjusted(v,gain) else v;val n=(adjusted.coerceIn(-1f,1f)*32767).toInt();buffer[offset++]=(n and 255).toByte();buffer[offset++]=(n ushr 8).toByte();if(offset==buffer.size){out.write(buffer);offset=0}}
                if(offset>0)out.write(buffer,0,offset)
            }
        }
    }
}
