package org.openoffline.translator.android.packages

import com.sun.net.httpserver.HttpServer
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class PackageSafetyTest {
    private fun sha(bytes: ByteArray) = PackageIntegrity.hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    private val payload = "offline model, exact pinned bytes".toByteArray()
    private fun part(url: String) = PackagePart("test-model", "model.bin", url, payload.size.toLong(), sha(payload))
    private fun pack() = OfflinePackage("test", "Test", PackageCategory.VOICE, "piper", setOf("en"), PackageKind.ARCHIVE,
        listOf(part("https://example.com/model")), listOf(PackageEntry("model.bin", payload.size.toLong(), sha(payload))))
    private fun temp() = Files.createTempDirectory("package-safety").toFile()
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected rejection") } catch (_: PackageIntegrityException) { }
    }

    @Test fun checksumAndLengthRejectAlteredModels() {
        val root = temp()
        try {
            val file = File(root, "model").apply { writeBytes(payload) }
            PackageIntegrity.verify(file, payload.size.toLong(), sha(payload))
            file.writeBytes(payload.copyOf().also { it[0] = 0 })
            rejects { PackageIntegrity.verify(file, payload.size.toLong(), sha(payload)) }
            rejects { PackageIntegrity.verify(file, payload.size.toLong() + 1, sha(payload)) }
        } finally { root.deleteRecursively() }
    }

    @Test fun manifestArchiveAcceptsOnlyDeclaredVerifiedFiles() {
        val root = temp()
        try {
            PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/model.bin", payload)), root, pack())
            assertArrayEquals(payload, File(root, "model.bin").readBytes())
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/../escape", payload)), root, pack()) }
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/model.bin", payload, '2')), root, pack()) }
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/unknown.bin", payload)), root, pack()) }
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/model.bin", payload.copyOf().also { it[0] = 0 })), root, pack()) }
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(ByteArray(1024)), root, pack()) }
            val duplicated = tar("test/model.bin", payload).dropLast(1024).toByteArray() + tar("test/model.bin", payload)
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(duplicated), root, pack()) }
            rejects { PackageIntegrity.extractTar(ByteArrayInputStream(tar("test/model.bin", payload) + byteArrayOf(1)), root, pack()) }
        } finally { root.deleteRecursively() }
    }

    @Test fun traversalPathsAndAbsolutePathsAreNeverAccepted() {
        listOf("../file", "/file", "a//b", "a/./b", "a/../b", "a\\b", "a\u0000b", "").forEach { assertFalse(it, PackageIntegrity.safePath(it)) }
        assertTrue(PackageIntegrity.safePath("espeak-ng-data/lang/en"))
    }

    @Test fun bzipCrcFailureNeverLeavesAnInstalledDirectory() {
        val root = temp()
        try {
            val archive = File(root, "voice.tar.bz2")
            BZip2CompressorOutputStream(archive.outputStream()).use { it.write(tar("test/model.bin", payload)) }
            val destination = File(root, "valid")
            PackageIntegrity.extract(archive, destination, pack())
            assertArrayEquals(payload, File(destination, "model.bin").readBytes())
            val corrupt = archive.readBytes().also { it[it.lastIndex - 1] = (it[it.lastIndex - 1].toInt() xor 0x40).toByte() }
            archive.writeBytes(corrupt)
            val rejected = File(root, "rejected")
            try { PackageIntegrity.extract(archive, rejected, pack()); fail("Expected damaged bzip2 rejection") }
            catch (_: IOException) { }
            assertFalse(rejected.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun resumesPartialResponseAtExactOffset() {
        val root = temp()
        val range = mutableListOf<String?>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/model") { exchange ->
            range += exchange.requestHeaders.getFirst("Range")
            val start = exchange.requestHeaders.getFirst("Range")!!.removePrefix("bytes=").removeSuffix("-").toInt()
            exchange.responseHeaders.add("Content-Range", "bytes $start-${payload.size - 1}/${payload.size}")
            exchange.sendResponseHeaders(206, (payload.size - start).toLong())
            exchange.responseBody.use { it.write(payload, start, payload.size - start) }
        }
        server.start()
        try {
            val file = File(root, "partial").apply { writeBytes(payload.take(9).toByteArray()) }
            ResumableDownload(true).download(part("http://127.0.0.1:${server.address.port}/model"), file, {}, {})
            assertEquals(listOf("bytes=9-"), range)
            assertArrayEquals(payload, file.readBytes())
        } finally { server.stop(0); root.deleteRecursively() }
    }

    @Test fun retriesDisconnectedResponseAndRestartsIfServerIgnoresRange() {
        val root = temp()
        val requests = AtomicInteger()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/model") { exchange ->
            exchange.sendResponseHeaders(200, payload.size.toLong())
            runCatching { exchange.responseBody.use { it.write(if (requests.incrementAndGet() == 1) payload.take(7).toByteArray() else payload) } }
            exchange.close()
        }
        server.start()
        try {
            val file = File(root, "partial")
            ResumableDownload(true).download(part("http://127.0.0.1:${server.address.port}/model"), file, {}, {})
            assertEquals(2, requests.get())
            assertArrayEquals(payload, file.readBytes())
        } finally { server.stop(0); root.deleteRecursively() }
    }

    @Test fun rejectsIncorrectContentRangeWithoutAppending() {
        val root = temp()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/model") { exchange ->
            exchange.responseHeaders.add("Content-Range", "bytes 0-${payload.size - 1}/${payload.size}")
            exchange.sendResponseHeaders(206, payload.size.toLong())
            runCatching { exchange.responseBody.use { it.write(payload) } }
        }
        server.start()
        try {
            val file = File(root, "partial").apply { writeBytes(payload.take(7).toByteArray()) }
            rejects { ResumableDownload(true).download(part("http://127.0.0.1:${server.address.port}/model"), file, {}, {}) }
            assertEquals(7L, file.length())
        } finally { server.stop(0); root.deleteRecursively() }
    }

    @Test fun pausePreservesPartialAndDoesNotRetry() {
        val root = temp()
        val stopped = AtomicBoolean()
        val requests = AtomicInteger()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/model") { exchange ->
            requests.incrementAndGet()
            exchange.sendResponseHeaders(200, payload.size.toLong())
            exchange.responseBody.use { it.write(payload) }
        }
        server.start()
        try {
            val file = File(root, "partial")
            try {
                ResumableDownload(true).download(part("http://127.0.0.1:${server.address.port}/model"), file,
                    { if (stopped.get()) throw DownloadStopped() }, { stopped.set(true) })
                fail("Expected pause")
            } catch (_: DownloadStopped) { }
            assertTrue(file.length() > 0)
            assertEquals(1, requests.get())
        } finally { server.stop(0); root.deleteRecursively() }
    }

    @Test fun sharedCatalogHasRealHashesAndHonestPlatformConstraints() {
        var root = File(System.getProperty("user.dir"))
        while (!File(root, "assets/catalogs/models.json").exists()) root = root.parentFile ?: error("Repository root not found")
        val catalog = PackageCatalog.load { File(root, "assets/catalogs/$it").readText() }
        assertTrue(catalog.size > 75)
        assertEquals(5780090304L, catalog.single { it.id == PackageCatalog.INDEX_ID }.downloadBytes)
        val compact = catalog.single { it.id == PackageCatalog.INDEX2B_ID }
        assertEquals(1312164352L, compact.downloadBytes)
        assertEquals("044b313d29342bd3b2c77cbb64023ca0d209bd9b3247763f9d162767ef2d746a", compact.parts.single().sha256)
        assertEquals(PackageCategory.TRANSLATION, compact.category)
        assertEquals(PackageCatalog.MULTILINGUAL_BACKEND, compact.backend)
        assertEquals(catalog.single { it.id == PackageCatalog.INDEX_ID }.languages, compact.languages)
        assertTrue(compact.parts.single().remoteURL.contains("/resolve/3a0eca6ce931d88d00614d427ab3ed8ff0743902/"))
        assertEquals(PackageCatalog.INDEX_MODELS.values.map { it.second }.toSet(), catalog.filter { it.backend in PackageCatalog.INDEX_MODELS }.map { it.id }.toSet())
        assertTrue(catalog.single { it.backend == "supertonic" }.supports("ru"))
        assertFalse(catalog.single { it.backend == "supertonic" }.supports("zh"))
        assertTrue(catalog.filter { it.backend == "coreml" }.all { it.unavailableReason != null })
        assertEquals(2, catalog.single { it.id == "mms-tts-ban-onnx" }.parts.size)
        assertTrue(catalog.any { it.backend == "ocr-detector" && it.unavailableReason == null })
        assertEquals(setOf("en", "ru", "uk", "be"), catalog.single { it.id == PackageCatalog.DEFAULT_TRANSLATION_ID }.languages)
        assertNull(catalog.single { it.id == PackageCatalog.DEFAULT_TRANSLATION_ID }.unavailableReason)
        assertNull(catalog.single { it.backend == "wayu" }.unavailableReason)
        assertNull(catalog.single { it.backend == "omnivoice" }.unavailableReason)
    }

    private fun tar(name: String, content: ByteArray, type: Char = '0'): ByteArray {
        val header = ByteArray(512)
        fun field(offset: Int, value: String) { value.toByteArray().copyInto(header, offset) }
        field(0, name); field(100, "0000644"); field(124, content.size.toString(8).padStart(11, '0'))
        (148..155).forEach { header[it] = 32 }; header[156] = type.code.toByte()
        field(148, header.sumOf { it.toInt() and 255 }.toString(8).padStart(6, '0') + "\u0000 ")
        return ByteArrayOutputStream().apply {
            write(header); write(content)
            write(ByteArray((512 - content.size % 512) % 512)); write(ByteArray(1024))
        }.toByteArray()
    }
}
