package org.openoffline.translator.android

import android.graphics.Bitmap
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.openoffline.translator.inference.OcrBlock
import org.openoffline.translator.inference.OcrLayout
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Bundled models: recognition is local and never waits for a network download.
 * Called by the single media worker; task owns a snapshot until ML Kit completes,
 * even when the user cancels and the camera releases its original bitmap. */
class MlKitOcr : java.io.Closeable {
    private class Entry(val script: OcrRouting.Script, val recognizer: TextRecognizer, var users: Int = 0, var retired: Boolean = false)
    private var cached: Entry? = null
    private var closed = false
    @Synchronized private fun acquire(script: OcrRouting.Script): Entry {
        check(!closed) { "OCR is closed" }
        cached?.takeIf { it.script == script }?.let { it.users++; return it }
        retire()
        val recognizer = when (script) {
            OcrRouting.Script.LATIN -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            OcrRouting.Script.CHINESE -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
            OcrRouting.Script.DEVANAGARI -> TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
            OcrRouting.Script.JAPANESE -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
            OcrRouting.Script.KOREAN -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        }
        return Entry(script, recognizer, users = 1).also { cached = it }
    }
    @Synchronized private fun retire() {
        cached?.let { it.retired = true; if (it.users == 0) it.recognizer.close() }
        cached = null
    }
    @Synchronized private fun release(entry: Entry) {
        entry.users--; if (entry.retired && entry.users == 0) entry.recognizer.close()
    }
    @Synchronized override fun close() { closed = true; cancel(); retire() }

    private val generation = AtomicLong()
    fun cancel() { generation.incrementAndGet() }

    fun recognize(bitmap: Bitmap, script: OcrRouting.Script, isCancelled: () -> Boolean = { false }): List<OcrBlock> {
        check(Looper.myLooper() != Looper.getMainLooper()) { "OCR must run on the media worker" }
        val epoch = generation.get()
        fun checkCancelled() {
            if (generation.get() != epoch || isCancelled()) throw CancellationException("OCR cancelled")
        }
        checkCancelled()
        val entry = acquire(script)
        val recognizer = entry.recognizer
        val snapshot = try { checkNotNull(bitmap.copy(Bitmap.Config.ARGB_8888, false)) }
            catch (e: Exception) { release(entry); throw e }
        val imageWidth = snapshot.width; val imageHeight = snapshot.height
        val completed = CountDownLatch(1)
        val task = try { recognizer.process(InputImage.fromBitmap(snapshot, 0)) }
            catch (e: Exception) { snapshot.recycle(); release(entry); throw e }
        task.addOnCompleteListener(Executor { it.run() }) {
            try { snapshot.recycle(); release(entry) } finally { completed.countDown() }
        }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (!completed.await(25, TimeUnit.MILLISECONDS)) {
            checkCancelled()
            check(System.nanoTime() < deadline) { "OCR timed out" }
        }
        checkCancelled()
        check(task.isSuccessful) { task.exception?.localizedMessage ?: "OCR failed" }
        return OcrLayout.group(task.result.textBlocks.flatMap { block -> block.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            val left = (box.left.toFloat() / imageWidth).coerceIn(0f, 1f)
            val top = (box.top.toFloat() / imageHeight).coerceIn(0f, 1f)
            val right = (box.right.toFloat() / imageWidth).coerceIn(0f, 1f)
            val bottom = (box.bottom.toFloat() / imageHeight).coerceIn(0f, 1f)
            line.text.takeIf { it.isNotBlank() && right > left && bottom > top }?.let {
                OcrBlock(it, left, top, right, bottom)
            }
        })
    }
}
