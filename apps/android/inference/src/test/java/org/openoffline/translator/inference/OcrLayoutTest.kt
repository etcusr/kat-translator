package org.openoffline.translator.inference
import org.junit.Assert.*
import org.junit.Test
class OcrLayoutTest {
    @Test fun sharedAppleParagraphThresholdsMergeAdjacentAlignedLines(){
        val result=OcrLayout.group(listOf(OcrBlock("Second",.11f,.17f,.7f,.22f),OcrBlock("First",.1f,.1f,.6f,.15f)))
        assertEquals(1,result.size);assertEquals("First\nSecond",result.single().text)
        assertEquals(.1f,result.single().left,0f);assertEquals(.7f,result.single().right,0f)
    }
    @Test fun distinctColumnsAndDistantLinesRemainSeparate(){
        val input=listOf(OcrBlock("Left",.1f,.1f,.4f,.15f),OcrBlock("Right",.6f,.1f,.9f,.15f),OcrBlock("Footer",.1f,.8f,.9f,.85f))
        assertEquals(3,OcrLayout.group(input).size)
    }
    @Test fun paragraphSizeIsBoundedLikeApple(){
        assertEquals(2,OcrLayout.group(listOf(OcrBlock("A".repeat(250),.1f,.1f,.8f,.15f),OcrBlock("B".repeat(200),.1f,.17f,.8f,.22f))).size)
    }
}
