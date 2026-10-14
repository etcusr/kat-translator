package org.openoffline.translator.inference

/** Partition an entire recording; VAD selects pauses but never discards audio. */
object RecordedSpeechSegments {
    data class Slice(val start:Int,val end:Int,val overlapsPrevious:Boolean=false)
    const val RATE=16000
    const val WINDOW=512
    fun detect(samples:FloatArray,modelPath:String,guard:()->Unit):List<Slice> {
        if(samples.size<=30*RATE)return listOf(Slice(0,samples.size))
        val detector=MediaNative.vadCreate(modelPath.toByteArray(Charsets.UTF_8))
        check(detector!=0L) { "Speech boundary detector unavailable" }
        try {
            val activity=BooleanArray((samples.size+WINDOW-1)/WINDOW)
            for(i in activity.indices) {
                guard()
                val start=i*WINDOW
                activity[i]=MediaNative.vadAccept(detector,samples.copyOfRange(start,minOf(start+WINDOW,samples.size)))
            }
            return plan(samples.size,activity)
        } finally { MediaNative.vadFree(detector) }
    }
    fun plan(size:Int,activity:BooleanArray):List<Slice> {
        require(size>0)
        val pauses=mutableListOf<Int>()
        var quiet=-1
        for(i in 0..activity.size) {
            val speech=i<activity.size && activity[i]
            if(!speech && quiet<0)quiet=i
            if(speech && quiet>=0) {
                if(quiet>0 && i-quiet>=11)pauses+=((quiet+i)*WINDOW/2).coerceAtMost(size)
                quiet=-1
            }
        }
        val result=mutableListOf<Slice>();var start=0;var overlap=false
        while(start<size) {
            val maximum=minOf(size,start+30*RATE)
            val pause=pauses.firstOrNull { it>=start+15*RATE && it<=maximum && it<size-3*RATE }
            val end=pause ?: maximum
            result+=Slice(start,end,overlap)
            if(end==size)break
            overlap=pause==null
            start=if(overlap)end-RATE/2 else end
        }
        return result
    }
    /** Only forced cuts overlap. Ordinary pauses retain intentional repeated words. */
    fun append(previous:String,next:String,overlap:Boolean):String {
        if(previous.isBlank())return next.trim()
        if(next.isBlank())return previous
        if(!overlap)return "$previous ${next.trim()}"
        val a=previous.trim().split(Regex("\\s+"));val b=next.trim().split(Regex("\\s+"))
        fun key(s:String)=s.lowercase().filter { it.isLetterOrDigit() }
        val match=(minOf(12,a.size,b.size) downTo 1).firstOrNull { n ->
            a.takeLast(n).map(::key)==b.take(n).map(::key) && b.take(n).any { key(it).isNotEmpty() }
        } ?: 0
        return (a+b.drop(match)).joinToString(" ")
    }
}
