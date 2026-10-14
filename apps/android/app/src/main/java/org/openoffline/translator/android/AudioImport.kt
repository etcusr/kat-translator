package org.openoffline.translator.android

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioFormat
import android.net.Uri
import android.os.SystemClock
import java.io.File
import java.io.BufferedOutputStream
import java.nio.ByteOrder
import kotlin.math.floor

/** Decode/downmix/resample incrementally. A private PCM spool avoids retaining the entire
 * source-rate recording and its decoded/resampled copies in the Android Java heap. */
object AudioImport {
    fun decode(context:Context,uri:Uri,cancelled:()->Boolean):FloatArray {
        val extractor=MediaExtractor()
        var codec:MediaCodec?=null
        val spool=File.createTempFile("audio-import-",".pcm",context.cacheDir)
        try {
            extractor.setDataSource(context,uri,null)
            val track=(0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/")==true } ?: error("No audio track")
            extractor.selectTrack(track)
            val format=extractor.getTrackFormat(track)
            val decoder=MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec=decoder
            decoder.configure(format,null,null,0);decoder.start()
            var rate=format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels=format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding=AudioFormat.ENCODING_PCM_16BIT
            var sourceFrames=0L
            var nextSample=0.0
            var previous=0f
            var total=0
            var inputDone=false
            var outputDone=false
            var lastProgress=SystemClock.elapsedRealtime()
            val info=MediaCodec.BufferInfo()
            BufferedOutputStream(spool.outputStream(),65536).use { output ->
                fun writeSample(value:Float) {
                    check(total<16000*60*30) { "Audio exceeds the 30-minute limit" }
                    val n=(value.coerceIn(-1f,1f)*32767).toInt()
                    output.write(n and 255);output.write((n ushr 8) and 255);total++
                }
                while(!outputDone) {
                    check(!cancelled()) { "Cancelled" }
                    check(SystemClock.elapsedRealtime()-lastProgress<30_000) { "Audio decoder stopped responding" }
                    if(!inputDone) {
                        val index=decoder.dequeueInputBuffer(10_000)
                        if(index>=0) {
                            val buffer=decoder.getInputBuffer(index)!!
                            val n=extractor.readSampleData(buffer,0)
                            if(n<0) { decoder.queueInputBuffer(index,0,0,0,MediaCodec.BUFFER_FLAG_END_OF_STREAM);inputDone=true }
                            else { decoder.queueInputBuffer(index,0,n,extractor.sampleTime,0);extractor.advance() }
                            lastProgress=SystemClock.elapsedRealtime()
                        }
                    }
                    val index=decoder.dequeueOutputBuffer(info,10_000)
                    if(index==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val out=decoder.outputFormat
                        val newRate=out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        check(sourceFrames==0L || newRate==rate) { "Audio sample rate changes mid-stream" }
                        rate=newRate;channels=out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        encoding=out.getInteger(MediaFormat.KEY_PCM_ENCODING,AudioFormat.ENCODING_PCM_16BIT)
                        require(rate>0 && channels in 1..32 && encoding in setOf(AudioFormat.ENCODING_PCM_16BIT,AudioFormat.ENCODING_PCM_FLOAT)) { "Unsupported decoded audio format" }
                        lastProgress=SystemClock.elapsedRealtime()
                    } else if(index>=0) {
                        if(info.size>0) {
                            val buffer=decoder.getOutputBuffer(index)!!.duplicate().order(ByteOrder.nativeOrder())
                            buffer.position(info.offset);buffer.limit(info.offset+info.size)
                            val bytes=if(encoding==AudioFormat.ENCODING_PCM_FLOAT)4 else 2
                            val frames=info.size/(bytes*channels)
                            val mono=FloatArray(frames)
                            for(i in mono.indices) { var sum=0f;repeat(channels) { sum+=if(bytes==4)buffer.float else buffer.short/32768f };mono[i]=sum/channels }
                            val end=sourceFrames+frames
                            while(nextSample<end-1 && frames>0) {
                                val left=floor(nextSample).toLong()
                                val fraction=(nextSample-left).toFloat()
                                val a=if(left<sourceFrames)previous else mono[(left-sourceFrames).toInt()]
                                val b=mono[(left+1-sourceFrames).toInt()]
                                writeSample(a+(b-a)*fraction)
                                nextSample+=rate/16000.0
                            }
                            if(frames>0)previous=mono.last()
                            sourceFrames=end
                        }
                        outputDone=info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM!=0
                        decoder.releaseOutputBuffer(index,false)
                        lastProgress=SystemClock.elapsedRealtime()
                    }
                }
                while(nextSample<sourceFrames) { writeSample(previous);nextSample+=rate/16000.0 }
            }
            check(total>0) { "No audio samples" }
            val result=FloatArray(total)
            spool.inputStream().buffered(65536).use { input ->
                for(i in result.indices) {
                    if(i%16384==0)check(!cancelled()) { "Cancelled" }
                    val low=input.read();val high=input.read();check(low>=0 && high>=0) { "Incomplete audio spool" }
                    result[i]=((low or (high shl 8)).toShort()/32768f)
                }
            }
            return result
        } finally {
            try { codec?.stop() } catch(_:Exception) {}
            codec?.release();extractor.release();spool.delete()
        }
    }
}
