package org.openoffline.translator.inference

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class MediaNativeBoundaryTest {
    @Test fun cancellationFlagCanBeReleasedBeforeInference() {
        repeat(20) { val f=MediaNative.flagCreate();assertNotEquals(0L,f);MediaNative.flagCancel(f);MediaNative.flagFree(f) }
    }
    @Test fun whisperCorruptHeaderFailsWithoutCrashing() {
        val file=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"broken-whisper.bin")
        file.writeBytes("invalid".toByteArray())
        val flag=MediaNative.flagCreate()
        try { assertThrows(IllegalStateException::class.java) { MediaNative.whisper(file.path.toByteArray(),FloatArray(16000){.1f},"en".toByteArray(),flag) } }
        finally { MediaNative.flagFree(flag);file.delete() }
    }
    @Test fun cancelledRequestNeverLoadsMissingWhisper() {
        val flag=MediaNative.flagCreate();MediaNative.flagCancel(flag)
        try { assertNull(MediaNative.whisper("/missing".toByteArray(),FloatArray(16000),"en".toByteArray(),flag)) }
        finally { MediaNative.flagFree(flag) }
    }
    @Test fun recognizerMissingFileReturnsNoHandle() { assertEquals(0L,MediaNative.ocrLoad("/missing-ocr.onnx".toByteArray())) }
}
