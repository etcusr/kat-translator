package org.openoffline.translator.inference

import android.content.Context
import android.media.*
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Streaming playback with explicit ownership. Providing Context enables Android audio focus. */
class SpeechPlayer(context: Context? = null) : AutoCloseable {
    private val manager=context?.getSystemService(AudioManager::class.java)
    private class Playback(val player:AudioTrack,val focus:AudioFocusRequest?) {
        val released=AtomicBoolean(false)
    }
    private var playback:Playback?=null
    private var worker:Thread?=null
    private val running=AtomicBoolean(false)
    @Volatile var appliedGain=1.0;private set
    @Volatile var isPlaying=false;private set
    @Volatile var isPaused=false;private set
    private fun release(value:Playback){
        if(value.released.compareAndSet(false,true)){
            try{value.player.pause();value.player.flush();value.player.stop()}catch(_:IllegalStateException){}
            value.player.release();value.focus?.let{manager?.abandonAudioFocusRequest(it)}
        }
    }
    @Synchronized fun play(audio:SpeechAudio,speed:Float=1f,normalizeVolume:Boolean=false) {
        require(speed in .5f..2f);stop()
        val attributes=AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        var request:AudioFocusRequest?=null
        var player:AudioTrack?=null
        try {
            if(manager!=null){
                request=AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes).setOnAudioFocusChangeListener { change ->
                    synchronized(this){if(change<0 && playback?.focus===request)pause()}
                }.build()
                check(manager.requestAudioFocus(request)==AudioManager.AUDIOFOCUS_REQUEST_GRANTED){"Audio focus unavailable"}
            }
            val minimum=AudioTrack.getMinBufferSize(audio.sampleRate,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_FLOAT)
            check(minimum>0)
            val created=AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(AudioFormat.Builder().setSampleRate(audio.sampleRate).setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()).setBufferSizeInBytes(maxOf(minimum*2,8192)).setTransferMode(AudioTrack.MODE_STREAM).build()
            player=created;check(created.state==AudioTrack.STATE_INITIALIZED){"Audio playback unavailable"}
            created.playbackParams=PlaybackParams().setSpeed(speed).setPitch(1f)
            created.play()
            val session=Playback(created,request);playback=session;running.set(true);isPlaying=true;isPaused=false
            worker=Thread({
                try{
                    val gain=if(normalizeVolume)SpeechLoudness.recordingGain(audio.samples,audio.sampleRate) else null
                    appliedGain=gain ?: 1.0
                    val buffer=if(gain!=null)FloatArray(2048) else null
                    var offset=0
                    while(running.get()&&offset<audio.samples.size){
                        if(isPaused){Thread.sleep(20);continue}
                        val length=minOf(2048,audio.samples.size-offset)
                        if(buffer!=null)for(i in 0 until length)buffer[i]=SpeechLoudness.adjusted(audio.samples[offset+i],gain!!)
                        val count=created.write(buffer ?: audio.samples,if(buffer!=null)0 else offset,length,AudioTrack.WRITE_NON_BLOCKING)
                        if(count<0)break
                        if(count==0)Thread.sleep(10) else offset+=count
                    }
                    while(running.get()&&(created.playbackHeadPosition.toLong() and 0xffffffffL) < offset.toLong())Thread.sleep(20)
                }catch(_:InterruptedException){}catch(_:IllegalStateException){}
                finally{release(session);isPlaying=false;isPaused=false}
            },"kat-speech-play").also{it.start()}
        }catch(t:Throwable){
            running.set(false);isPlaying=false;isPaused=false
            val session=playback
            if(session!=null){release(session);playback=null}
            else{player?.release();request?.let{manager?.abandonAudioFocusRequest(it)}}
            throw t
        }
    }
    @Synchronized fun pause(){
        playback?.takeUnless{it.released.get()}?.let{try{it.player.pause();isPaused=true}catch(_:IllegalStateException){}}
    }
    @Synchronized fun resume(){
        playback?.takeUnless{it.released.get()}?.let{try{it.player.play();isPaused=false;isPlaying=true}catch(_:IllegalStateException){}}
    }
    /** Changing speed preserves the current position and an explicit pause. */
    @Synchronized fun setSpeed(speed:Float){
        require(speed in .5f..2f)
        playback?.takeUnless{it.released.get()}?.let {
            val paused=isPaused
            it.player.playbackParams=PlaybackParams().setSpeed(speed).setPitch(1f)
            if(paused)it.player.pause()
        }
    }
    @Synchronized fun stop(){
        running.set(false);worker?.interrupt();worker?.join();worker=null
        playback?.let(::release);playback=null;isPlaying=false;isPaused=false
    }
    override fun close(){stop()}
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
