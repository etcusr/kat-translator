package org.openoffline.translator.inference
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
@RunWith(AndroidJUnit4::class)
class NativeBoundaryTest {
    @Test fun missingModel() { assertThrows(IllegalStateException::class.java) { IndexEngine.open("/missing/model.gguf") } }
    @Test fun corruptedHeader() {
        val file=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"corrupt.gguf")
        file.writeBytes("GGUFbroken".toByteArray())
        try { assertThrows(IllegalStateException::class.java) { IndexEngine.open(file.path) } } finally { file.delete() }
    }
    @Test fun nativeUtf8RoundTrip() {
        val text="Привет 👋 ไทย e\u0301 <|im_end|>"
        assertEquals(text,String(NativeBridge.echo(IndexRequest.utf8(text)),Charsets.UTF_8))
    }
}
