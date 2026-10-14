package org.openoffline.translator.android

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.OpusEngine
import org.openoffline.translator.inference.OpusRoute
import org.openoffline.translator.inference.TranslationResult
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Root runs this serially under the Pixel thermal guard, with the real shared package. */
@RunWith(AndroidJUnit4::class)
class OpusDeviceTest {
    @Test fun realOpusSixDirectionsLimitsCancellationAndAppleTokenParity() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val context = inst.targetContext
        val packageDirectory = File(context.getExternalFilesDir(null), "packages/${OpusEngine.PACKAGE_ID}")
        val reportFile = File(context.getExternalFilesDir(null), "opus-acceptance.json")
        val cases = JSONArray()
        val report = JSONObject().put("backend", "ctranslate2-ruy-cpu").put("passed", false).put("cases", cases)
        fun stage(message: String) { inst.sendStatus(0, Bundle().apply { putString("stream", "\nOPUS: $message\n") }) }
        try {
            stage("verify exact shared package")
            val manifest = JSONArray(context.assets.open("opus-package.json").bufferedReader().use { it.readText() })
            for (i in 0 until manifest.length()) {
                val part = manifest.getJSONObject(i)
                val file = File(packageDirectory, part.getString("path"))
                assertTrue("Real OPUS package missing: ${part.getString("path")}", file.isFile)
                assertEquals(part.getLong("byteCount"), file.length())
                val digest = MessageDigest.getInstance("SHA-256")
                file.inputStream().use { input ->
                    val bytes = ByteArray(1024 * 1024)
                    while (true) { val n = input.read(bytes); if (n < 0) break; digest.update(bytes, 0, n) }
                }
                assertEquals(part.getString("sha256"), digest.digest().joinToString("") { "%02x".format(it) })
            }
            report.put("verifiedParts", manifest.length())
            OpusEngine.open(packageDirectory.path).use { engine ->
                stage("Apple source token-count parity")
                val fixtures = JSONObject(inst.context.assets.open("opus-token-parity.json").bufferedReader().use { it.readText() }).getJSONArray("cases")
                for (i in 0 until fixtures.length()) {
                    val row = fixtures.getJSONObject(i)
                    assertEquals(row.getInt("tokenCount"), engine.tokens(row.getString("text"), row.getString("source"), row.getString("target")))
                }
                report.put("tokenParityCases", fixtures.length())
                fun translate(text: String, source: String, target: String): String {
                    stage("$source → $target")
                    val started = System.nanoTime()
                    val result = engine.translate(text, source, target)
                    assertTrue("Expected real translation, got $result", result is TranslationResult.Success)
                    val output = (result as TranslationResult.Success).text
                    assertTrue(output.isNotBlank())
                    assertTrue("Time must survive translation: $output", output.contains("10:30"))
                    if (target == "en") assertTrue(output.any { it in 'a'..'z' || it in 'A'..'Z' })
                    else assertTrue(output.any { it in '\u0400'..'\u04FF' })
                    cases.put(JSONObject().put("source", source).put("target", target).put("input", text).put("output", output).put("seconds", (System.nanoTime() - started) / 1e9))
                    reportFile.writeText(report.toString(2))
                    return output
                }
                for (target in listOf("ru", "uk", "be")) translate("The train leaves at 10:30.", "en", target)
                translate("Поезд отправляется в 10:30.", "ru", "en")
                translate("Потяг відправляється о 10:30.", "uk", "en")
                translate("Цягнік адпраўляецца ў 10:30.", "be", "en")
                stage("input limit without truncation")
                assertEquals(TranslationResult.Limit, engine.translate("word ".repeat(600), "en", "ru"))
                stage("cancel then fresh request")
                val pool = Executors.newSingleThreadExecutor()
                try {
                    val future = pool.submit<TranslationResult> {
                        engine.translate("The meeting tomorrow requires a detailed and careful discussion of every planned activity. ".repeat(16), "en", "ru")
                    }
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                    var cancelled = false
                    while (!cancelled && !future.isDone && System.nanoTime() < deadline) {
                        cancelled = engine.cancel()
                        if (!cancelled) Thread.sleep(5)
                    }
                    assertTrue("Real native request never became cancellable", cancelled)
                    assertEquals(TranslationResult.Cancelled, future.get(30, TimeUnit.SECONDS))
                } finally { pool.shutdownNow() }
                translate("Поезд прибывает в 10:30.", "ru", "en")
                report.put("limitsPassed", true).put("cancelThenNewRequestPassed", true)
            }
            OpusEngine.open(packageDirectory.path).use { assertTrue(it.tokens("Hello", "en", "ru") > 0) }
            report.put("reloadPassed", true).put("passed", true)
        } finally { reportFile.writeText(report.toString(2)) }
    }
}

/** English package routes, as the catalog declares them (en-zle needs the target marker). */
private fun englishRoute(source: String, target: String) = if (source == "en")
    OpusRoute("en-zle", mapOf("ru" to ">>rus<<", "uk" to ">>ukr<<", "be" to ">>bel<<").getValue(target)) else OpusRoute("zle-en", "")
private fun OpusEngine.tokens(text: String, source: String, target: String) = tokens(text, englishRoute(source, target))
private fun OpusEngine.translate(text: String, source: String, target: String) = translate(text, englishRoute(source, target))
