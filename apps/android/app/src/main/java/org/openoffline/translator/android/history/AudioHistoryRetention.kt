package org.openoffline.translator.android.history

/** A saved row may own two files, each consuming a separate audio retention slot. */
data class AudioRetentionEntry(val id:String,val time:Long,val translationPath:String?,val originalPath:String?)

object AudioHistoryRetention {
    /** Pure policy. Caller removes only managed files absent from the returned set.
     * Newest rows first; equal timestamps retain input order; translation precedes original.
     * Zero count/age means unlimited independently, matching shared HistoryPolicy.
     */
    fun select(entries:List<AudioRetentionEntry>,limit:Int,days:Int,now:Long):Set<String> {
        require(limit in 0..10000 && days in 0..365)
        val oldest=if(days==0)Long.MIN_VALUE else now-days*86_400_000L
        val retained=linkedSetOf<String>()
        for(entry in entries.withIndex().sortedWith(compareByDescending<IndexedValue<AudioRetentionEntry>>{it.value.time}.thenBy{it.index})){
            if(entry.value.time<oldest)continue
            for(path in listOfNotNull(entry.value.translationPath,entry.value.originalPath)){
                if(limit>0 && retained.size>=limit)return retained
                retained+=path
            }
        }
        return retained
    }
}
