package org.openoffline.translator.android

/** Mirrors the modal owners and navigation destinations in the shared Apple views. */
internal object SheetNavigation {
    data class Destination(val route:String,val parents:List<String>)
    fun close(route:String,parents:List<String>,back:Boolean):Destination {
        fun pop()=if(parents.isEmpty())Destination("",emptyList()) else Destination(parents.last(),parents.dropLast(1))
        fun owner(name:String):Destination {
            val index=parents.lastIndexOf(name)
            return if(index<0)pop() else Destination(name,parents.take(index))
        }
        if(back)return pop()
        return when {
            route.startsWith("modelInfo:") || route.startsWith("modelLanguages:")->owner("models")
            route=="setup" || route=="opusDirections"->owner("models")
            route=="historyImage"->owner("history")
            route=="models" && parents.lastOrNull()=="settings"->pop()
            // Settings destinations inherit its Done action. Language voice settings
            // inherit the language picker's Done action. Both dismiss their owner.
            else->Destination("",emptyList())
        }
    }
}
