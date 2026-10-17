package org.openoffline.translator.android

/** A tab/selection change revokes even an already running native load's right to publish ready. */
internal class RecognitionPreparation {
    data class Ticket(val epoch:Long,val key:String)
    private var epoch=0L
    private var current:Ticket?=null
    private var ready:String?=null
    private var deferred:Ticket?=null
    private var deferredEpoch=0L
    @Synchronized fun defer(key:String) { deferred=Ticket(deferredEpoch,key) }
    @Synchronized fun cancelDeferred() { deferredEpoch++;deferred=null }
    @Synchronized fun consumeDeferred(key:String):Boolean {
        val request=deferred;deferred=null
        return request!=null && request.epoch==deferredEpoch && request.key==key
    }
    @Synchronized fun begin(key:String):Ticket { ready=null;return Ticket(++epoch,key).also { current=it } }
    @Synchronized fun complete(ticket:Ticket):Boolean {
        if(ticket!=current)return false
        ready=ticket.key;return true
    }
    @Synchronized fun invalidate(clearDeferred:Boolean=true) { epoch++;current=null;ready=null;if(clearDeferred)cancelDeferred() }
    @Synchronized fun isReady(key:String)=ready==key
}
