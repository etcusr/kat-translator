package org.openoffline.translator.android

/** Phrase ledger shared by the main recording ticker and the one native worker.
 * Like iOS, boundaries need one second of silence and at least two seconds of audio.
 * A snapshot is capped at 30 seconds; a longer unfinished phrase falls back to final ASR.
 */
class RecordingPreview(val source:String,val target:String,val verify:Boolean,val speak:Boolean) {
    data class Block(val source:String,val translation:String)
    data class Prepared(val end:Int,val language:String?,val blocks:List<Block>) {
        val sourceText get()=blocks.joinToString(" ") { it.source }
        val translation get()=blocks.joinToString(" ") { it.translation }
    }
    private var committed=0
    private var lastOfferedSpeech=0
    private var inFlight=false
    private var language:String?=null
    private val blocks=mutableListOf<Block>()
    @Volatile var cancelled=false;private set
    @Volatile var suspended=false;private set
    @Synchronized fun next(position:Int,speechEnd:Int):IntRange? {
        if(cancelled || suspended || inFlight || speechEnd<=lastOfferedSpeech || position-speechEnd<16000 || position-committed<32000)return null
        if(position-committed>480000) { suspended=true;return null }
        lastOfferedSpeech=speechEnd;inFlight=true
        return committed until position
    }
    @Synchronized fun commit(range:IntRange,text:String,translated:String,detected:String):Boolean {
        inFlight=false
        if(cancelled || suspended || range.first!=committed || !completeSentence(text) || translated.isBlank())return false
        committed=range.last+1;language=language ?: detected
        blocks+=Block(text.trim(),translated.trim());return true
    }
    @Synchronized fun finishAttempt() { inFlight=false }
    @Synchronized fun suspend() { suspended=true }
    @Synchronized fun cancel() { cancelled=true;suspended=true }
    @Synchronized fun prepared()=Prepared(committed,language,blocks.toList())
    companion object {
        fun completeSentence(text:String)=text.trimEnd().lastOrNull() in setOf('.','!','?','。','！','？')
    }
}
