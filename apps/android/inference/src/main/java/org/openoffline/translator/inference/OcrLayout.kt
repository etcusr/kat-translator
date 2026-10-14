package org.openoffline.translator.inference

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Identical paragraph grouping thresholds to shared/apple/Camera/HybridOCR.swift. */
object OcrLayout {
    fun group(input:List<OcrBlock>):List<OcrBlock> {
        val output=mutableListOf<OcrBlock>()
        for(block in input.sortedBy{it.top}){
            val last=output.lastOrNull()
            if(last!=null){
                val gap=block.top-last.bottom
                if(abs(last.left-block.left)<.025f && gap>=-.002f && gap<(block.bottom-block.top)*.65f && block.bottom-last.top<.23f && last.text.length+block.text.length<400){
                    output[output.lastIndex]=OcrBlock(last.text+"\n"+block.text,min(last.left,block.left),last.top,max(last.right,block.right),block.bottom)
                    continue
                }
            }
            output+=block
        }
        return output
    }
}
