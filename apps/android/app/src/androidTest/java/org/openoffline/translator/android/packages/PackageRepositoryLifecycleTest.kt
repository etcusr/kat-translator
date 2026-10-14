package org.openoffline.translator.android.packages

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real repository/disk lifecycle with tiny pinned bytes and per-instance HTTPS transport.
 * No user model directory, network request, singleton replacement or permission change.
 */
@RunWith(AndroidJUnit4::class)
class PackageRepositoryLifecycleTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun await(message: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        while (!predicate() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
        assertTrue(message, predicate())
    }

    @Test fun rapidResumeKeepsQueuedWorkAndInstallsOnlyVerifiedBytes() {
        withFixture { root, transfer, packs, repository ->
            val primary = packs[0]
            val secondary = packs[1]
            val gate = transfer.blockNext(primary)
            repository.start(primary.id)
            assertTrue("First transfer never reached its controlled read", gate.entered.await(10, TimeUnit.SECONDS))
            val partial = File(root, "packages/.downloads/${primary.id}/${primary.parts.single().id}.partial")
            val offset = partial.length()
            assertTrue("The pause must interrupt a real partially written file", offset > 0 && offset < primary.downloadBytes)
            repository.start(secondary.id)
            repository.pause(secondary.id)
            repository.start(secondary.id)
            repository.pause(primary.id)
            assertEquals(PackagePhase.PAUSED, repository.states.value[primary.id]?.phase)
            // Keep the old read blocked after disconnect: resume must enqueue before unwind.
            repository.start(primary.id)
            assertEquals("Rapid resume was lost behind the old operation", PackagePhase.QUEUED, repository.states.value[primary.id]?.phase)
            gate.release.countDown()
            await("Both resumed packages must complete") { packs.all { repository.states.value[it.id]?.phase == PackagePhase.INSTALLED } }
            packs.forEach { pack ->
                val installed = requireNotNull(repository.installedPath(pack.id))
                PackageIntegrity.verify(installed, pack.downloadBytes, pack.parts.single().sha256)
                assertArrayEquals(transfer.payload(pack), installed.readBytes())
            }
            assertEquals(listOf(0L, offset), transfer.requests.filter { it.id == primary.id }.map { it.offset })
            assertEquals(1, transfer.requests.count { it.id == secondary.id })
            assertTrue("Resume must send the saved ETag", transfer.requests.last { it.id == primary.id }.etag == "\"fixture-v1\"")
            assertFalse(File(root, "packages/.downloads/${primary.id}").exists())

            var lease: java.io.Closeable? = null
            await("Installed package must become leasable") {
                if (lease == null) lease = runCatching { repository.acquire(primary.id) }.getOrNull()
                lease != null
            }
            try {
                repository.remove(primary.id)
                await("Removing an in-use model must be rejected") { repository.states.value[primary.id]?.phase == PackagePhase.ERROR }
                assertNotNull(repository.installedPath(primary.id))
            } finally { lease!!.close() }
            repository.remove(primary.id)
            await("Removal must succeed after lease release") { repository.states.value[primary.id]?.phase == PackagePhase.ABSENT }
            assertNull(repository.installedPath(primary.id))
        }
    }

    @Test fun cancelDiscardsPartialAndRetryBeginsAtZero() {
        withFixture { root, transfer, packs, repository ->
            val pack = packs.first()
            val gate = transfer.blockNext(pack)
            repository.start(pack.id)
            assertTrue(gate.entered.await(10, TimeUnit.SECONDS))
            repository.cancel(pack.id)
            gate.release.countDown()
            await("Cancel must finish without retrying") { repository.states.value[pack.id]?.phase == PackagePhase.ABSENT }
            assertFalse(File(root, "packages/.downloads/${pack.id}").exists())
            assertNull(repository.installedPath(pack.id))
            repository.start(pack.id)
            await("Fresh start after cancel must install") { repository.states.value[pack.id]?.phase == PackagePhase.INSTALLED }
            assertEquals(listOf(0L, 0L), transfer.requests.map { it.offset })
        }
    }

    @Test fun reopenedRepositoryResumesPartialAndRejectsTamperedInstallation() {
        val root = Files.createTempDirectory(context.cacheDir.toPath(), "package-lifecycle-").toFile()
        val transfer = FixtureTransport()
        val packs = transfer.packages
        var repository = newRepository(root, transfer)
        try {
            val pack = packs.first()
            val gate = transfer.blockNext(pack)
            repository.start(pack.id)
            assertTrue(gate.entered.await(10, TimeUnit.SECONDS))
            val partialBytes = repository.states.value.getValue(pack.id).downloadedBytes
            repository.close()
            gate.release.countDown()
            awaitClosed(root)

            repository = newRepository(root, transfer)
            assertEquals(PackagePhase.PAUSED, repository.states.value[pack.id]?.phase)
            assertEquals(partialBytes, repository.states.value[pack.id]?.downloadedBytes)
            repository.start(pack.id)
            await("Reopened repository must resume its partial") { repository.states.value[pack.id]?.phase == PackagePhase.INSTALLED }
            assertEquals(listOf(0L, partialBytes), transfer.requests.map { it.offset })
            val file = requireNotNull(repository.installedPath(pack.id))
            repository.close()
            awaitClosed(root)
            val bytes = file.readBytes().also { it[0] = (it[0].toInt() xor 1).toByte() }
            file.writeBytes(bytes)
            file.setLastModified(file.lastModified() + 2_000)
            repository = newRepository(root, transfer)
            assertEquals(PackagePhase.ERROR, repository.states.value[pack.id]?.phase)
            assertNull("Corrupted receipt-backed file cannot be exposed to inference", repository.installedPath(pack.id))
            assertFalse(File(root, "packages/${pack.id}.receipt.json").exists())
        } finally {
            transfer.releaseAll()
            repository.close()
            awaitClosed(root)
            root.deleteRecursively()
        }
    }

    @Test fun digestFailureCannotPublishAndImmediateRetryCanRecover() {
        withFixture { root, transfer, packs, repository ->
            val pack = packs.first()
            transfer.corrupted.add(pack.id)
            repository.start(pack.id)
            await("Wrong digest must fail") { repository.states.value[pack.id]?.phase == PackagePhase.ERROR }
            assertNull(repository.installedPath(pack.id))
            assertFalse(File(root, "packages/${pack.id}.bin").exists())
            assertFalse(File(root, "packages/${pack.id}.receipt.json").exists())
            assertFalse(File(root, "packages/.downloads/${pack.id}/${pack.parts.single().id}.partial").exists())
            transfer.corrupted.remove(pack.id)
            repository.start(pack.id)
            await("Retry after digest failure must install clean bytes") { repository.states.value[pack.id]?.phase == PackagePhase.INSTALLED }
            assertArrayEquals(transfer.payload(pack), requireNotNull(repository.installedPath(pack.id)).readBytes())
        }
    }

    private fun withFixture(test: (File, FixtureTransport, List<OfflinePackage>, PackageRepository) -> Unit) {
        val root = Files.createTempDirectory(context.cacheDir.toPath(), "package-lifecycle-").toFile()
        val transfer = FixtureTransport()
        val repository = newRepository(root, transfer)
        try { test(root, transfer, transfer.packages, repository) }
        finally {
            transfer.releaseAll()
            repository.close()
            awaitClosed(root)
            root.deleteRecursively()
        }
    }

    private fun newRepository(root: File, transfer: FixtureTransport): PackageRepository =
        PackageRepository(context, root, transfer.packages) { ResumableDownload(openConnection = transfer::connect) }
            .also { repo -> await("Isolated catalog restoration did not finish") { repo.restored.value } }

    private fun awaitClosed(root: File) {
        await("Repository must release its exclusive store lock") {
            runCatching {
                RandomAccessFile(File(root, "packages/.lock"), "rw").channel.use { channel ->
                    channel.tryLock()?.use { true } ?: false
                }
            }.getOrDefault(false)
        }
    }

    private class Gate {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
    }
    private data class Request(val id: String, val offset: Long, val etag: String?)
    private class FixtureTransport {
        private val bytes = mapOf(
            "fixture-first" to ByteArray(512 * 1024) { (it * 17).toByte() },
            "fixture-second" to ByteArray(256 * 1024) { (it * 31 + 1).toByte() },
        )
        val packages = bytes.map { (id, data) ->
            val sha = PackageIntegrity.hex(MessageDigest.getInstance("SHA-256").digest(data))
            OfflinePackage(id, id, PackageCategory.OCR, "ocr", setOf("en"), PackageKind.FILE,
                listOf(PackagePart(id, "model.bin", "https://fixture.invalid/$id", data.size.toLong(), sha)),
                listOf(PackageEntry("model.bin", data.size.toLong(), sha)))
        }
        val requests = CopyOnWriteArrayList<Request>()
        val corrupted: MutableSet<String> = ConcurrentHashMap.newKeySet()
        private val pending = ConcurrentHashMap<String, ConcurrentLinkedQueue<Gate>>()
        private val gates = CopyOnWriteArrayList<Gate>()
        fun payload(pack: OfflinePackage) = bytes.getValue(pack.id)
        fun blockNext(pack: OfflinePackage): Gate = Gate().also {
            gates += it
            pending.getOrPut(pack.id) { ConcurrentLinkedQueue() }.add(it)
        }
        fun releaseAll() = gates.forEach { it.release.countDown() }
        fun connect(url: URL): HttpURLConnection {
            require(url.protocol == "https" && url.host == "fixture.invalid")
            val id = url.path.removePrefix("/")
            val data = bytes.getValue(id).let { bytes -> if (id in corrupted) bytes.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() } else bytes }
            val gate = pending[id]?.poll()
            return object : HttpURLConnection(url) {
                @Volatile var disconnected = false
                var offset = 0
                var responseStarted = false
                override fun connect() { }
                override fun disconnect() { disconnected = true }
                override fun usingProxy() = false
                override fun getResponseCode(): Int {
                    if (!responseStarted) {
                        responseStarted = true
                        offset = getRequestProperty("Range")?.removePrefix("bytes=")?.removeSuffix("-")?.toInt() ?: 0
                        requests += Request(id, offset.toLong(), getRequestProperty("If-Range"))
                    }
                    return if (offset == 0) 200 else 206
                }
                override fun getHeaderField(name: String): String? = when (name) {
                    "Content-Length" -> (data.size - offset).toString()
                    "Content-Range" -> "bytes $offset-${data.size - 1}/${data.size}"
                    "ETag" -> "\"fixture-v1\""
                    else -> null
                }
                override fun getInputStream(): InputStream = object : InputStream() {
                    var cursor = offset
                    var gated = false
                    override fun read(): Int {
                        val one = ByteArray(1)
                        return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 255
                    }
                    override fun read(output: ByteArray, off: Int, len: Int): Int {
                        if (!gated && gate != null && cursor - offset >= 32 * 1024) {
                            gated = true
                            gate.entered.countDown()
                            if (!gate.release.await(10, TimeUnit.SECONDS)) throw IOException("Fixture read timed out")
                        }
                        if (disconnected) throw IOException("Fixture disconnected")
                        if (cursor == data.size) return -1
                        val count = minOf(len, 8 * 1024, data.size - cursor)
                        data.copyInto(output, off, cursor, cursor + count)
                        cursor += count
                        return count
                    }
                }
            }
        }
    }
}
