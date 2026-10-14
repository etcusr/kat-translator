package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class MediaContractTest {
    @Test fun detectorUsesPublishedBgrChannelOrder() {
        // Solid red: B=0,G=0,R=1, with the official ImageNet channel normalization.
        assertArrayEquals(floatArrayOf(-2.117904f,-2.035714f,2.64f),OcrDecoding.detectorInput(intArrayOf(0xffff0000.toInt())),.00001f)
    }
    @Test fun ctcKeepsDuplicatesSeparatedByBlankAndUnicode() {
        assertEquals("лл🙂",OcrDecoding.ctc(intArrayOf(0,1,1,0,1,2,2,0),listOf("","л","🙂")))
    }
    @Test(expected=IllegalArgumentException::class) fun mismatchedDictionaryFails() {
        OcrDecoding.ctc(intArrayOf(3),listOf("","a"))
    }
    @Test fun detectorRejectsNoiseAndNormalizesTextBox() {
        val pixels=FloatArray(64*32)
        pixels[0]=1f
        for(y in 12..18)for(x in 20..40)pixels[y*64+x]=.9f
        val boxes=OcrDecoding.boxes(pixels,64,32)
        assertEquals(1,boxes.size)
        assertTrue(boxes[0][0]<20f/64 && boxes[0][2]>40f/64)
        assertTrue(boxes[0].all{it in 0f..1f})
    }
    @Test fun emptyImageHasNoInventedText() { assertTrue(OcrDecoding.boxes(FloatArray(64*32),64,32).isEmpty()) }
    @Test(expected=IllegalArgumentException::class) fun pcmRejectsNan() { SpeechAudio(floatArrayOf(Float.NaN),16000) }
    @Test fun wavHasActualEngineRateAndCorrectDuration() {
        val file=File.createTempFile("kat-media-test",".wav")
        try {
            SpeechPlayer.writeWav(file,SpeechAudio(floatArrayOf(-1f,0f,1f),24000))
            val bytes=file.readBytes()
            assertEquals(50,bytes.size)
            assertEquals("RIFF",String(bytes.copyOfRange(0,4)))
            assertEquals("WAVE",String(bytes.copyOfRange(8,12)))
            assertEquals(24000,(bytes[24].toInt() and 255) or ((bytes[25].toInt() and 255) shl 8))
            assertEquals(6,bytes[40].toInt())
        }finally{file.delete()}
    }
}
