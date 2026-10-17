package org.openoffline.translator.inference

/** One native model, owned by OfflineMedia's operation monitor. Never caches a failed load. */
internal class NativeModelCache(private val release:(Long)->Unit):AutoCloseable {
    private var key:String?=null
    private var handle=0L
    var loads=0;private set
    fun acquire(identity:String,create:()->Long):Long {
        if(handle!=0L && key==identity)return handle
        close()
        val loaded=create();check(loaded!=0L) { "Model could not be loaded" }
        handle=loaded;key=identity;loads++
        return loaded
    }
    override fun close() { if(handle!=0L)release(handle);handle=0;key=null }
}
