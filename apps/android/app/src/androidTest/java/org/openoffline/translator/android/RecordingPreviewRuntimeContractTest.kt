package org.openoffline.translator.android

import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog
import org.openoffline.translator.android.packages.PackagePhase
import org.openoffline.translator.android.packages.PackageRepository
import org.openoffline.translator.inference.IndexEngine
import org.openoffline.translator.inference.IndexRequest
import org.openoffline.translator.inference.OfflineMedia
import org.openoffline.translator.inference.Transcript
import org.openoffline.translator.inference.TranslationResult
import java.io.File

/** Actual shared PCM, real Whisper/Index and the production phrase ledger. This accepts
 * the bounded-snapshot/native-result contract, not AudioRecord or ViewModel ticker dispatch.
 * No microphone injection, fake native result, network, preferences or history writes. */
@RunWith(AndroidJUnit4::class)
class RecordingPreviewRuntimeContractTest {
    @get:Rule val environment=UiTestEnvironment.wrap()
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private fun report(message:String)=instrumentation.sendStatus(0,Bundle().apply { putString("stream","\nPREVIEW $message\n") })

    @Test fun boundedSnapshotCommitsRealTranslationAndFullRecordingCanBeVerified() {
        val context=instrumentation.targetContext
        val fixture=File(context.cacheDir,"preview-runtime-acceptance.wav")
        instrumentation.context.assets.open("media-asr-en.fixture").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        val store=PackageRepository(context)
        fun installed(id:String):File {
            val deadline=SystemClock.elapsedRealtime()+180_000
            while(SystemClock.elapsedRealtime()<deadline) {
                store.installedPath(id)?.let { return it }
                val status=store.states.value[id]
                check(status?.phase!=PackagePhase.ERROR) { "Fixture verification failed for $id: ${status?.message}" }
                Thread.sleep(100)
            }
            error("Install exact shared fixture $id before running this test")
        }
        try {
            val whisperId="whisper-large-v3-turbo-f16"
            val whisper=installed(whisperId)
            val index=installed(PackageCatalog.INDEX_ID)
            val original=AudioImport.decode(context,Uri.fromFile(fixture)) { false }
            assertTrue("Known fixture must leave room inside the 30-second snapshot bound",original.size in 32_000..464_000)
            // Preserve every decoded fixture sample. One second of true zero-amplitude
            // silence provides the same boundary condition as recorder VAD timestamps.
            val recorded=original.copyOf(original.size+16_000)
            val preview=RecordingPreview(source="en",target="ru",verify=true,speak=false)
            assertNull("Speech with no trailing silence must not enter ASR",preview.next(original.size,original.size))
            val range=requireNotNull(preview.next(recorded.size,original.size))
            assertEquals(0,range.first)
            assertEquals(recorded.size,range.last+1)
            assertTrue(range.count()<=480_000)
            val snapshot=recorded.copyOfRange(range.first,range.last+1)
            assertArrayEquals(original,snapshot.copyOfRange(0,original.size),0f)
            assertNull("Only one native phrase may be in flight",preview.next(recorded.size,original.size))

            fun recognize(samples:FloatArray,stage:String):Transcript {
                report("$stage ASR start samples=${samples.size}")
                val started=SystemClock.elapsedRealtime()
                val transcript=store.acquire(whisperId).use { OfflineMedia().use { it.transcribe(whisper.path,samples,"en") } }
                assertEquals("en",transcript.language)
                for(word in listOf("not","cancel","order","train"))assertTrue("$stage missing '$word': ${transcript.text}",transcript.text.contains(word,true))
                report("$stage ASR complete seconds=${(SystemClock.elapsedRealtime()-started)/1000.0}")
                return transcript
            }
            val provisional=recognize(snapshot,"bounded snapshot")
            assertTrue("Only a naturally completed native sentence may commit: ${provisional.text}",RecordingPreview.completeSentence(provisional.text))
            // Whisper has been closed before loading Index. There is never a second
            // native model owner alongside either operation.
            report("bounded snapshot Index start")
            val translated=store.acquire(PackageCatalog.INDEX_ID).use {
                IndexEngine.open(index.path,gpu=true,flash=true,mtp=true).use { engine ->
                    val request=IndexRequest(provisional.text,"ru")
                    assertTrue("Known fixture fits the unchanged Index request budget",IndexRequest.fits(engine.tokens(request).size,engine.sourceTokenCount(provisional.text)))
                    val result=engine.translate(request)
                    assertTrue("Real Index must finish without truncation: $result",result is TranslationResult.Success)
                    (result as TranslationResult.Success).text
                }
            }
            assertTrue("Expected actual Russian order translation: $translated",translated.contains("заказ",true))
            assertTrue(preview.commit(range,provisional.text,translated,provisional.language))
            val prepared=preview.prepared()
            assertEquals(recorded.size,prepared.end)
            assertEquals(provisional.text.trim(),prepared.sourceText)
            assertEquals(translated.trim(),prepared.translation)
            assertEquals(1,prepared.blocks.size)
            assertNull("The committed audio must not be offered twice",preview.next(recorded.size,original.size))

            // Verification uses the complete original recording, not the provisional
            // transcript. Index was closed before this second genuine Whisper pass.
            assertTrue(preview.verify)
            val verified=recognize(original,"full recording verification")
            assertTrue(verified.text.isNotBlank())
            assertEquals("Verification must not silently corrupt the provisional ledger",prepared,preview.prepared())
            preview.cancel()
            assertFalse("A completed but cancelled session cannot publish another result",preview.commit(range,verified.text,translated,verified.language))
            report("PASS bounded native snapshot, one committed phrase, no overlap, actual full-ASR verification, cancellation prevents publish; microphone/ticker not covered")
        } finally {
            store.close();fixture.delete()
        }
    }
}
