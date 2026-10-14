package org.openoffline.translator.android.packages

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

internal class DownloadStopped : IOException()

/** Pinned size/hash are authoritative; Range/ETag only accelerate recovery. */
internal class ResumableDownload(
    private val allowHttpForTests: Boolean = false,
    private val openConnection: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
    private val checkNetwork: () -> Unit = {},
) {
    @Volatile private var connection: HttpURLConnection? = null
    fun disconnect() { connection?.disconnect() }

    fun download(part: PackagePart, file: File, check: () -> Unit, progress: (Long) -> Unit) {
        file.parentFile!!.mkdirs()
        if (file.length() > part.byteCount) file.delete()
        if (file.length() == part.byteCount) return
        var lastError: IOException? = null
        repeat(3) { attempt ->
            check()
            try { transfer(part, file, check, progress); return }
            catch (stop: DownloadStopped) { throw stop }
            catch (error: PackageIntegrityException) { throw error }
            catch (error: IOException) {
                lastError = error; check()
                if (attempt < 2) repeat(5 * (attempt + 1)) { check(); Thread.sleep(100) }
            }
        }
        throw requireNotNull(lastError)
    }

    private fun transfer(part: PackagePart, file: File, check: () -> Unit, progress: (Long) -> Unit) {
        var url = URL(part.remoteURL)
        val offset = file.length()
        val tagFile = File(file.path + ".etag")
        val etag = tagFile.takeIf { it.isFile }?.readText()?.takeIf { !it.contains('\r') && !it.contains('\n') }
        var redirects = 0
        while (true) {
            check()
            require(url.protocol == "https" || (allowHttpForTests && url.protocol == "http")) { "Разрешены только HTTPS-загрузки" }
            val conn = openConnection(url).apply {
                connectTimeout = 30_000; readTimeout = 30_000; instanceFollowRedirects = false
                setRequestProperty("Accept-Encoding", "identity")
                if (offset > 0) {
                    setRequestProperty("Range", "bytes=$offset-")
                    if (etag != null) setRequestProperty("If-Range", etag)
                }
            }
            connection = conn
            try {
                val response = conn.responseCode
                if (response in listOf(301, 302, 303, 307, 308)) {
                    if (++redirects > 8) throw IOException("Слишком много перенаправлений")
                    url = URL(url, conn.getHeaderField("Location") ?: throw IOException("Нет адреса перенаправления"))
                    continue
                }
                if (response != 200 && response != 206) throw IOException("Сервер вернул HTTP $response")
                val append = response == 206
                if (append) {
                    val range = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(conn.getHeaderField("Content-Range").orEmpty())
                        ?: throw PackageIntegrityException("Сервер вернул неверный диапазон")
                    val (start, end, total) = range.destructured
                    if (start.toLong() != offset || total.toLong() != part.byteCount || end.toLong() != part.byteCount - 1)
                        throw PackageIntegrityException("Сервер вернул другой файл")
                }
                val expected = part.byteCount - if (append) offset else 0
                val length = conn.getHeaderFieldLong("Content-Length", -1)
                if (length >= 0 && length != expected) throw PackageIntegrityException("Размер ответа не совпадает с каталогом")
                conn.getHeaderField("ETag")?.takeIf { !it.contains('\r') && !it.contains('\n') }?.let { tagFile.writeText(it) }
                if (conn.getHeaderField("ETag") == null) tagFile.delete()
                var copied = if (append) offset else 0L
                conn.inputStream.buffered(256 * 1024).use { input ->
                    FileOutputStream(file, append).use { output ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            check(); checkNetwork(); val n = input.read(buffer); if (n < 0) break
                            if (copied + n > part.byteCount) throw PackageIntegrityException("Ответ больше ожидаемого файла")
                            output.write(buffer, 0, n); copied += n; progress(copied)
                        }
                        output.fd.sync()
                    }
                }
                if (copied != part.byteCount) throw IOException("Загрузка прервалась. Можно продолжить")
                return
            } finally { conn.disconnect(); connection = null }
        }
    }
}
