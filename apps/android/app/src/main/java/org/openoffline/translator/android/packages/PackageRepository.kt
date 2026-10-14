package org.openoffline.translator.android.packages

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** One process owner shared by UI and foreground service. Storage mutations are serialized. */
class PackageRepository internal constructor(
    context: Context,
    rootOverride: File?,
    catalogOverride: List<OfflinePackage>?,
    private val transferFactory: () -> ResumableDownload,
) : Closeable {
    constructor(context: Context) : this(context, null, null, {
        val allowCellular = DownloadAccess.allowCellular(context)
        ResumableDownload(
            openConnection = { DownloadAccess.openConnection(context, it, allowCellular) },
            checkNetwork = { DownloadAccess.requireNetwork(context, allowCellular) },
        )
    })
    private val app = context.applicationContext
    private val root = rootOverride ?: requireNotNull(app.getExternalFilesDir(null)) { "Хранилище приложения недоступно" }
    private val packagesRoot = File(root, "packages").apply { mkdirs() }
    private val downloadsRoot = File(packagesRoot, ".downloads").apply { mkdirs() }
    private val stagingRoot = File(packagesRoot, ".staging").apply { mkdirs() }
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "offline-packages").apply { isDaemon = true } }
    private val lockChannel = RandomAccessFile(File(packagesRoot, ".lock"), "rw").channel
    private val storageLock = requireNotNull(lockChannel.tryLock()) { "Хранилище уже открыто другим загрузчиком" }
    val catalog: List<OfflinePackage> = catalogOverride ?: PackageCatalog.load(app.assets)
    private val byId = catalog.associateBy { it.id }
    private val mutableStates = MutableStateFlow(catalog.associate { it.id to PackageStatus(totalBytes = it.downloadBytes) })
    val states: StateFlow<Map<String, PackageStatus>> = mutableStates.asStateFlow()
    private val mutableRestored = MutableStateFlow(false)
    val restored: StateFlow<Boolean> = mutableRestored.asStateFlow()
    private val operations = ConcurrentHashMap<String, Operation>()
    private val verifiedPaths = ConcurrentHashMap<String, File>()
    private val leases = ConcurrentHashMap<String, Int>()
    @Volatile private var closed = false
    @Volatile var restorationSeconds=0.0;private set
    @Volatile var startupFullVerifications=0;private set
    @Volatile var startupCachedPackages=0;private set

    private class Operation(val transfer: ResumableDownload) {
        @Volatile var stop: PackagePhase? = null
        @Volatile var running = false
        fun check() { if (stop != null || Thread.currentThread().isInterrupted) throw DownloadStopped() }
    }

    init { executor.execute {
        val start=System.nanoTime()
        try { catalog.forEach { if (!closed) restore(it) } } finally {
            restorationSeconds=(System.nanoTime()-start)/1e9
            mutableRestored.value = !closed
        }
    } }

    /** Only paths whose catalog identity and installed file stamps have been verified are returned. */
    fun installedPath(id: String): File? = verifiedPaths[id]?.takeIf { it.exists() }
    fun file(id: String, relativePath: String): File? {
        val pack = byId[id] ?: return null
        if (pack.files.none { it.path == relativePath }) return null
        val installed = installedPath(id) ?: return null
        return (if (pack.kind == PackageKind.FILE) installed else PackageIntegrity.child(installed, relativePath)).takeIf { it.isFile }
    }

    /** Runtime holders may prevent removal while native code is reading/mapping these files. */
    @Synchronized fun acquire(id: String): Closeable {
        check(installedPath(id) != null) { "Пакет не установлен" }
        check(operations[id] == null) { "Пакет изменяется" }
        leases[id] = (leases[id] ?: 0) + 1
        var released = false
        return Closeable { synchronized(this) { if (!released) { leases[id] = ((leases[id] ?: 1) - 1).coerceAtLeast(0); released = true } } }
    }

    fun start(id: String) = enqueue(id) { pack, operation -> install(pack, operation) }
    fun pauseAll() = states.value.filterValues { it.busy }.keys.forEach(::pause)
    fun cancelAll() = states.value.filterValues { it.busy || it.phase == PackagePhase.PAUSED }.keys.forEach(::cancel)
    /** Upper bound for confirmation: the server may reject a resume and resend a part. */
    fun maximumDownloadBytes(ids: Collection<String>): Long = ids.distinct().mapNotNull(byId::get)
        .filter { installedPath(it.id) == null && states.value[it.id]?.busy != true }
        .filter { pack -> pack.parts.any { partFile(pack, it).length() != it.byteCount } }
        .sumOf { it.downloadBytes }

    /** Conservative batch preflight; each package checks again immediately before installation. */
    fun checkSpace(ids: Collection<String>) {
        val selected = ids.distinct().map { requireNotNull(byId[it]) { "Unknown package: $it" } }.filter { installedPath(it.id) == null }
        val needed = selected.sumOf { spaceRequired(it) }
        check(root.usableSpace >= needed + 128L * 1024 * 1024) { "Недостаточно свободного места. Нужно ещё ${needed / 1048576} МБ" }
    }
    @Synchronized fun pause(id: String) { operations[id]?.let {
        it.stop = PackagePhase.PAUSED; it.transfer.disconnect()
        if (!it.running) operations.remove(id, it)
        byId[id]?.let { pack -> state(pack, PackagePhase.PAUSED, downloaded(pack)) }
    } }
    @Synchronized fun cancel(id: String) {
        val op = operations[id]
        if (op != null) {
            op.stop = PackagePhase.ABSENT; op.transfer.disconnect()
            if (!op.running) {
                operations.remove(id, op)
                val pack = byId[id] ?: return
                downloadDirectory(pack).deleteRecursively()
                state(pack, if (installedPath(id) != null) PackagePhase.INSTALLED else PackagePhase.ABSENT)
            }
        }
        else enqueue(id, allowUnavailable = true) { pack, _ ->
            downloadDirectory(pack).deleteRecursively()
            state(pack, if (installedPath(id) != null) PackagePhase.INSTALLED else PackagePhase.ABSENT)
        }
    }

    fun remove(id: String) {
        enqueue(id, allowUnavailable = true) { pack, _ ->
            synchronized(this) { check((leases[id] ?: 0) == 0) { "Модель используется. Сначала остановите перевод или озвучку" } }
            verifiedPaths.remove(id)
            // Drop the receipt first: partially removed data must never appear usable.
            receipt(pack).delete()
            val target = target(pack)
            check(if (target.isDirectory) target.deleteRecursively() else !target.exists() || target.delete()) { "Не удалось удалить пакет" }
            downloadDirectory(pack).deleteRecursively()
            File(stagingRoot, id).deleteRecursively()
            state(pack, PackagePhase.ABSENT)
        }
    }

    /** Import a single model/archive or one component of a multipart package via the system picker. */
    fun importFile(id: String, uri: Uri) {
        enqueue(id) { pack, operation ->
            val directory = downloadDirectory(pack).apply { mkdirs() }
            ensureSpace(pack)
            val temporary = File(directory, "import.partial")
            val limit = pack.parts.maxOf { it.byteCount }
            var bytes = 0L
            try {
                state(pack, PackagePhase.DOWNLOADING, message = "Импорт файла")
                requireNotNull(app.contentResolver.openInputStream(uri)) { "Не удалось открыть файл" }.use { input ->
                    FileOutputStream(temporary).use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            operation.check(); val n = input.read(buffer); if (n < 0) break
                            bytes += n; check(bytes <= limit) { "Файл больше ожидаемого пакета" }
                            output.write(buffer, 0, n); state(pack, PackagePhase.DOWNLOADING, bytes, "Импорт файла")
                        }
                        output.fd.sync()
                    }
                }
                val candidates = pack.parts.filter { it.byteCount == bytes }
                check(candidates.isNotEmpty()) { "Размер файла не совпадает с каталогом" }
                val part = candidates.firstOrNull {
                    try { PackageIntegrity.verify(temporary, it.byteCount, it.sha256, operation::check); true }
                    catch (_: PackageIntegrityException) { false }
                } ?: throw PackageIntegrityException("Файл не соответствует SHA-256 пакета")
                atomicMove(temporary, partFile(pack, part))
                if (pack.parts.all { partFile(pack, it).length() == it.byteCount }) install(pack, operation)
                else state(pack, PackagePhase.PAUSED, downloaded(pack), "Компонент импортирован. Импортируйте остальные или продолжите загрузку")
            } finally { temporary.delete() }
        }
    }

    @Synchronized private fun enqueue(id: String, allowUnavailable: Boolean = false, action: (OfflinePackage, Operation) -> Unit) {
        if (closed) return
        val pack = byId[id] ?: return
        // A resume may arrive while the previous HTTP socket/verification is unwinding.
        // The single executor guarantees the replacement starts only after old cleanup.
        if (operations[id]?.stop == null && operations.containsKey(id) && states.value[id]?.busy == true) return
        if (!allowUnavailable && pack.unavailableReason != null) {
            state(pack, PackagePhase.ERROR, message = pack.unavailableReason); return
        }
        val operation = Operation(transferFactory())
        operations[id] = operation
        state(pack, PackagePhase.QUEUED, downloaded(pack))
        executor.execute {
            synchronized(this) {
                if (operations[id] !== operation) return@execute
                operation.running = true
            }
            try { operation.check(); action(pack, operation) }
            catch (_: DownloadStopped) {
                val phase = operation.stop ?: PackagePhase.PAUSED
                if (phase == PackagePhase.ABSENT) downloadDirectory(pack).deleteRecursively()
                synchronized(this) {
                    if (operations[id] === operation) state(pack, if (installedPath(id) != null) PackagePhase.INSTALLED else phase, downloaded(pack))
                }
            } catch (error: Exception) {
                synchronized(this) {
                    if (operations[id] === operation) state(pack, PackagePhase.ERROR, downloaded(pack), error.message ?: "Не удалось установить пакет")
                }
            } finally {
                File(stagingRoot, id).deleteRecursively()
                operations.remove(id, operation)
            }
        }
    }

    private fun install(pack: OfflinePackage, operation: Operation) {
        if (installedPath(pack.id) != null) { state(pack, PackagePhase.INSTALLED, pack.downloadBytes); return }
        ensureSpace(pack)
        downloadDirectory(pack).mkdirs()
        var completed = 0L
        for (part in pack.parts) {
            operation.check()
            val file = partFile(pack, part)
            state(pack, PackagePhase.DOWNLOADING, completed + file.length())
            operation.transfer.download(part, file, operation::check) { state(pack, PackagePhase.DOWNLOADING, completed + it) }
            state(pack, PackagePhase.VERIFYING, completed + part.byteCount)
            try { PackageIntegrity.verify(file, part.byteCount, part.sha256, operation::check) }
            catch (error: PackageIntegrityException) { file.delete(); File(file.path + ".etag").delete(); throw error }
            completed += part.byteCount
        }
        operation.check()
        state(pack, PackagePhase.INSTALLING, pack.downloadBytes)
        val staging = File(stagingRoot, pack.id)
        staging.deleteRecursively()
        when (pack.kind) {
            PackageKind.FILE -> {
                val file = partFile(pack, pack.parts.single())
                operation.check()
                publishFile(pack, file)
            }
            PackageKind.ARCHIVE -> {
                PackageIntegrity.extract(partFile(pack, pack.parts.single()), staging, pack, operation::check)
                publishDirectory(pack, staging, operation)
            }
            PackageKind.FILES, PackageKind.PIPER -> {
                staging.mkdirs()
                for (part in pack.parts) {
                    operation.check()
                    val path = if (pack.kind == PackageKind.PIPER) "model.onnx" else part.path
                    val output = PackageIntegrity.child(staging, path)
                    output.parentFile!!.mkdirs()
                    // Keep download components until commit so interrupted installation can resume offline.
                    copyChecked(partFile(pack, part), output, operation)
                }
                if (pack.kind == PackageKind.PIPER) {
                    FileOutputStream(File(staging, "model.onnx"), true).use {
                        it.write(Base64.getDecoder().decode(requireNotNull(pack.metadataSuffix))); it.fd.sync()
                    }
                    File(staging, "tokens.txt").writeText(requireNotNull(pack.tokens))
                }
                PackageIntegrity.verifyDirectory(staging, pack.files, operation::check)
                publishDirectory(pack, staging, operation)
            }
        }
        verifiedPaths[pack.id] = target(pack)
        downloadDirectory(pack).deleteRecursively()
        state(pack, PackagePhase.INSTALLED, pack.downloadBytes)
    }

    private fun copyChecked(source: File, target: File, operation: Operation) {
        source.inputStream().use { input -> FileOutputStream(target).use { output ->
            val bytes = ByteArray(1024 * 1024)
            while (true) { operation.check(); val n = input.read(bytes); if (n < 0) break; output.write(bytes, 0, n) }
            output.fd.sync()
        } }
    }

    private fun publishFile(pack: OfflinePackage, staging: File) {
        val final = target(pack)
        final.parentFile!!.mkdirs()
        // Same external volume; an atomic rename preserves the existing Index filename.
        atomicMove(staging, final)
        saveReceipt(pack)
    }

    private fun publishDirectory(pack: OfflinePackage, staging: File, operation: Operation) {
        operation.check()
        val final = target(pack)
        val backup = File(packagesRoot, ".backup-${pack.id}")
        backup.deleteRecursively()
        if (final.exists()) atomicMove(final, backup)
        try {
            atomicMove(staging, final)
            saveReceipt(pack)
            backup.deleteRecursively()
        } catch (error: Exception) {
            final.deleteRecursively()
            if (backup.exists()) atomicMove(backup, final)
            throw error
        }
    }

    private fun restore(pack: OfflinePackage) {
        try {
            val final = target(pack)
            val backup = File(packagesRoot, ".backup-${pack.id}")
            if (!final.exists() && backup.exists()) atomicMove(backup, final)
            if (!final.exists()) {
                if (downloaded(pack) > 0) state(pack, PackagePhase.PAUSED, downloaded(pack))
                return
            }
            val saved = runCatching { JSONObject(receipt(pack).readText()) }.getOrNull()
            val stamps = stamps(pack)
            if (saved?.optString("identity") != identity(pack) || saved?.optString("stamps") != stamps) {
                startupFullVerifications++
                state(pack, PackagePhase.VERIFYING, pack.downloadBytes)
                val check = { if (closed) throw DownloadStopped() }
                if (pack.kind == PackageKind.FILE) PackageIntegrity.verify(final, pack.parts.single().byteCount, pack.parts.single().sha256, check)
                else PackageIntegrity.verifyDirectory(final, pack.files, check)
                saveReceipt(pack)
            } else startupCachedPackages++
            verifiedPaths[pack.id] = final
            backup.deleteRecursively()
            state(pack, PackagePhase.INSTALLED, pack.downloadBytes)
        } catch (_: DownloadStopped) { /* Leaving a file without a receipt forces re-verification next launch. */ }
        catch (error: Exception) { receipt(pack).delete(); state(pack, PackagePhase.ERROR, message = error.message ?: "Проверка пакета не пройдена") }
    }

    private fun ensureSpace(pack: OfflinePackage) {
        val needed = spaceRequired(pack)
        check(root.usableSpace >= needed + 128L * 1024 * 1024) { "Недостаточно свободного места. Нужно ещё ${needed / 1048576} МБ" }
    }
    private fun spaceRequired(pack: OfflinePackage): Long {
        val remaining = pack.parts.sumOf { (it.byteCount - partFile(pack, it).length()).coerceAtLeast(0) }
        val expanded = if (pack.kind == PackageKind.FILE) 0L else pack.expandedBytes
        return remaining + expanded
    }

    private fun target(pack: OfflinePackage): File = when {
        pack.id == PackageCatalog.INDEX_ID -> File(root, PackageCatalog.INDEX_FILENAME)
        pack.kind == PackageKind.FILE -> File(packagesRoot, "${pack.id}.bin")
        else -> File(packagesRoot, pack.id)
    }
    private fun receipt(pack: OfflinePackage) = File(packagesRoot, "${pack.id}.receipt.json")
    private fun downloadDirectory(pack: OfflinePackage) = File(downloadsRoot, pack.id)
    private fun partFile(pack: OfflinePackage, part: PackagePart) = File(downloadDirectory(pack), part.id + ".partial")
    private fun downloaded(pack: OfflinePackage): Long = pack.parts.sumOf { partFile(pack, it).length().coerceAtMost(it.byteCount) }
    private fun identity(pack: OfflinePackage): String = PackageIntegrity.hex(MessageDigest.getInstance("SHA-256").digest(
        (pack.id + "\n" + pack.files.joinToString("\n") { "${it.path}\t${it.byteCount}\t${it.sha256}" }).toByteArray()))
    private fun stamps(pack: OfflinePackage): String = pack.files.joinToString("\n") {
        val file = if (pack.kind == PackageKind.FILE) target(pack) else PackageIntegrity.child(target(pack), it.path)
        val attributes = Files.readAttributes(file.toPath(), BasicFileAttributes::class.java)
        check(attributes.isRegularFile && attributes.size() == it.byteCount) { "Неполный пакет" }
        "${it.path}\t${attributes.size()}\t${attributes.lastModifiedTime()}\t${attributes.fileKey()}"
    }
    private fun saveReceipt(pack: OfflinePackage) {
        val final = receipt(pack)
        val temporary = File(final.path + ".tmp")
        FileOutputStream(temporary).use { it.write(JSONObject().put("identity", identity(pack)).put("stamps", stamps(pack)).toString().toByteArray()); it.fd.sync() }
        atomicMove(temporary, final)
    }
    private fun atomicMove(source: File, destination: File) {
        Files.move(source.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }
    @Synchronized private fun state(pack: OfflinePackage, phase: PackagePhase, bytes: Long = 0, message: String? = null) {
        mutableStates.value = mutableStates.value + (pack.id to PackageStatus(phase, bytes, pack.downloadBytes, message))
    }
    @Synchronized override fun close() {
        if (closed) return
        closed = true
        operations.values.forEach { it.stop = PackagePhase.PAUSED; it.transfer.disconnect() }
        executor.execute { storageLock.release(); lockChannel.close() }
        executor.shutdown()
    }
}
