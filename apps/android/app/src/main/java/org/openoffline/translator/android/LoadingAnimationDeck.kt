package org.openoffline.translator.android

/** Same shuffle bag as iOS: every clip once per round, no repeat at round boundaries.
 * One shared instance survives separate processing screens in this process. */
internal class LoadingAnimationDeck(private val clips:List<String>,private val shuffle:(List<String>)->List<String> ={it.shuffled()}) {
    private val remaining=mutableListOf<String>()
    private var previous:String?=null
    @Synchronized fun next():String? {
        if(remaining.isEmpty()) {
            remaining.addAll(shuffle(clips))
            if(remaining.size>1 && remaining.last()==previous) {
                val last=remaining.lastIndex;val first=remaining[0];remaining[0]=remaining[last];remaining[last]=first
            }
        }
        return remaining.removeLastOrNull()?.also { previous=it }
    }
}
