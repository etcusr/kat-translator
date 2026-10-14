package org.openoffline.translator.android.packages

import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.IOException
import java.security.MessageDigest

class PackageIntegrityException(message: String) : IOException(message)

/** Fail-closed archive reader: only exact manifest files and ordinary directories are accepted. */
internal object PackageIntegrity {
    fun safePath(path: String): Boolean = path.isNotEmpty() && !path.startsWith('/') && !path.contains('\\') && !path.contains('\u0000') &&
        path.split('/').all { it.isNotEmpty() && it != "." && it != ".." }

    fun child(root: File, path: String): File {
        require(safePath(path)) { "Недопустимый путь файла" }
        val file = File(root, path)
        require(file.canonicalPath.startsWith(root.canonicalPath + File.separator)) { "Недопустимый путь файла" }
        return file
    }

    fun verify(file: File, size: Long, digest: String, check: () -> Unit = {}) {
        if (!file.isFile || file.length() != size) throw PackageIntegrityException("Файл скачан не полностью")
        val stamp = file.lastModified()
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) { check(); val n = input.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
        }
        if (file.length() != size || file.lastModified() != stamp || hex(hash.digest()) != digest)
            throw PackageIntegrityException("Проверка SHA-256 не пройдена. Скачайте файл заново")
    }

    fun verifyDirectory(directory: File, files: List<PackageEntry>, check: () -> Unit = {}) {
        files.forEach { verify(child(directory, it.path), it.byteCount, it.sha256, check) }
    }

    fun extract(archive: File, destination: File, pack: OfflinePackage, check: () -> Unit = {}) {
        require(!destination.exists())
        check(destination.mkdirs()) { "Не удалось создать папку пакета" }
        var complete = false
        try {
            BZip2CompressorInputStream(archive.inputStream().buffered(), true).use { input ->
                extractTar(input, destination, pack, check)
            }
            complete = true
        } finally { if (!complete) destination.deleteRecursively() }
    }

    internal fun extractTar(input: InputStream, destination: File, pack: OfflinePackage, check: () -> Unit = {}) {
        val expected = pack.files.associateBy { it.path }
        val seen = mutableSetOf<String>()
        var entries = 0
        fun read(size: Int): ByteArray {
            val bytes = ByteArray(size)
            var offset = 0
            while (offset < size) {
                check()
                val n = input.read(bytes, offset, size - offset)
                if (n <= 0) throw PackageIntegrityException("Архив оборван")
                offset += n
            }
            return bytes
        }
        fun field(bytes: ByteArray, start: Int, end: Int): String {
            val until = (start until end).firstOrNull { bytes[it] == 0.toByte() } ?: end
            return bytes.copyOfRange(start, until).toString(Charsets.UTF_8)
        }
        fun invalid(message: String): Nothing = throw PackageIntegrityException(message)
        while (true) {
            val header = read(512)
            if (header.all { it == 0.toByte() }) {
                if (!read(512).all { it == 0.toByte() } || seen != expected.keys) invalid("Архив неполон")
                // Consume and validate bzip2 CRC/footer, with bounded zero tar padding.
                var padding = 0
                val bytes = ByteArray(4096)
                while (true) {
                    check(); val n = input.read(bytes); if (n < 0) break
                    padding += n
                    if (padding > 10240 || (0 until n).any { bytes[it] != 0.toByte() }) invalid("Лишние данные в архиве")
                }
                return
            }
            if (++entries > 2048) invalid("Слишком много файлов в архиве")
            val checksum = field(header, 148, 156).trim().toLongOrNull(8)
            val actual = header.indices.sumOf { if (it in 148..155) 32L else (header[it].toInt() and 255).toLong() }
            if (checksum != actual) invalid("Повреждён заголовок архива")
            val prefix = field(header, 345, 500)
            val name = ((if (prefix.isEmpty()) "" else "$prefix/") + field(header, 0, 100)).removeSuffix("/")
            if (!safePath(name) || (name != pack.archiveRoot && !name.startsWith(pack.archiveRoot + "/"))) invalid("Небезопасный путь в архиве")
            val relative = name.removePrefix(pack.archiveRoot).removePrefix("/")
            val size = field(header, 124, 136).trim().toLongOrNull(8) ?: invalid("Неверный размер файла")
            if (size < 0) invalid("Неверный размер файла")
            when (header[156].toInt()) {
                '5'.code -> { if (size != 0L) invalid("Неверная папка архива"); continue }
                0, '0'.code -> Unit
                else -> invalid("Ссылки и расширенные заголовки архива запрещены")
            }
            val spec = expected[relative] ?: invalid("Неизвестный файл в архиве")
            if (size != spec.byteCount || !seen.add(relative)) invalid("Файл архива не совпадает с каталогом")
            val target = child(destination, relative)
            target.parentFile!!.mkdirs()
            val hash = MessageDigest.getInstance("SHA-256")
            FileOutputStream(target).use { output ->
                var remaining = size
                while (remaining > 0) {
                    val block = read(minOf(remaining, 1024 * 1024).toInt())
                    output.write(block); hash.update(block); remaining -= block.size
                }
                output.fd.sync()
            }
            if (hex(hash.digest()) != spec.sha256) invalid("Файл архива не прошёл SHA-256")
            if (size % 512 != 0L) read((512 - size % 512).toInt())
        }
    }

    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
}
