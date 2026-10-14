package org.openoffline.translator.android

import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog
import org.openoffline.translator.android.packages.PackageKind
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID

/** Test-only bridge: shell reads pushed fixtures; app UID owns every installation write. */
@RunWith(AndroidJUnit4::class)
class AppOwnedPackageFixtureTest {
    @Test fun importExactSharedPackage() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val context = inst.targetContext
        val args = InstrumentationRegistry.getArguments()
        val id = requireNotNull(args.getString("packageId")) { "Pass -e packageId <shared catalog id>" }
        require(id != PackageCatalog.INDEX_ID) { "The installed Index model must never be replaced by fixture setup" }
        val pack = PackageCatalog.load(context.assets).single { it.id == id }
        val fixtureRoot = args.getString("fixtureRoot", "/data/local/tmp/kat-media-fixtures")!!
        require(fixtureRoot.startsWith('/') && !fixtureRoot.contains('\u0000'))
        val base = requireNotNull(context.getExternalFilesDir(null))
        val packages = File(base, "packages").apply { check(isDirectory || mkdirs()) }
        val destination = File(packages, if (pack.kind == PackageKind.FILE) "$id.bin" else id)
        val temporary = File(packages, ".fixture-$id-${UUID.randomUUID()}")
        val backup = File(packages, ".fixture-previous-$id")
        fun stage(message: String) = inst.sendStatus(0, Bundle().apply { putString("stream", "\nFixture $id: $message\n") })
        fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
        RandomAccessFile(File(packages, ".lock"), "rw").channel.use { channel ->
            val lock = requireNotNull(channel.tryLock()) { "Close the running UI/repository before fixture installation" }
            try {
                check(packages.usableSpace > pack.expandedBytes + 128L * 1024 * 1024) { "Insufficient device space" }
                check(temporary.mkdirs())
                for (entry in pack.files) {
                    val outputFile = File(temporary, entry.path)
                    require(outputFile.canonicalPath.startsWith(temporary.canonicalPath + File.separator))
                    outputFile.parentFile!!.mkdirs()
                    val hash = MessageDigest.getInstance("SHA-256")
                    var count = 0L
                    stage("copy ${entry.path}")
                    // UiAutomation launches Runtime.exec, which does not parse shell
                    // quoting. Feed a quoted script to a real shell's stdin instead.
                    val pipes = inst.uiAutomation.executeShellCommandRw("sh")
                    ParcelFileDescriptor.AutoCloseInputStream(pipes[0]).use { input ->
                        ParcelFileDescriptor.AutoCloseOutputStream(pipes[1]).use { command ->
                            command.write(("exec cat " + quote("$fixtureRoot/$id/${entry.path}") + "\n").toByteArray(Charsets.UTF_8))
                        }
                        FileOutputStream(outputFile).use { output ->
                            val bytes = ByteArray(1024 * 1024)
                            while (true) {
                                val n = input.read(bytes); if (n < 0) break
                                count += n
                                check(count <= entry.byteCount) { "Fixture larger than pinned manifest" }
                                hash.update(bytes, 0, n); output.write(bytes, 0, n)
                            }
                            output.fd.sync()
                        }
                    }
                    assertEquals("Fixture size: ${entry.path}", entry.byteCount, count)
                    assertEquals("Fixture SHA-256: ${entry.path}", entry.sha256, hash.digest().joinToString("") { "%02x".format(it) })
                }
                // Drop stale metadata; normal app startup independently re-verifies the new files.
                File(packages, "$id.receipt.json").delete()
                backup.deleteRecursively()
                if (destination.exists()) Files.move(destination.toPath(), backup.toPath(), StandardCopyOption.ATOMIC_MOVE)
                try {
                    val source = if (pack.kind == PackageKind.FILE) File(temporary, pack.files.single().path) else temporary
                    Files.move(source.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
                    backup.deleteRecursively()
                } catch (error: Throwable) {
                    if (!destination.exists() && backup.exists()) Files.move(backup.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
                    throw error
                }
                assertTrue("Target must be writable by the app", destination.canWrite())
                stage("verified ${pack.files.size} files; installed by app UID at ${destination.path}")
            } finally { temporary.deleteRecursively(); lock.release() }
        }
    }
}
