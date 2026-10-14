package org.openoffline.translator.android.packages

import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.io.InputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest

class DownloadAccessTest {
    @Test fun mobilePermissionNeverOverridesMissingNetwork() {
        for (allowed in listOf(false, true)) {
            assertFalse(DownloadNetworkState.UNKNOWN.canDownload(allowed))
            assertFalse(DownloadNetworkState.OFFLINE.canDownload(allowed))
            assertTrue(DownloadNetworkState.WIFI.canDownload(allowed))
            assertTrue(DownloadNetworkState.WIRED.canDownload(allowed))
            assertEquals(allowed, DownloadNetworkState.CELLULAR.canDownload(allowed))
            assertEquals(allowed, DownloadNetworkState.EXPENSIVE.canDownload(allowed))
        }
    }

    @Test fun meteredWifiAndUnknownVpnCostRequireExplicitPermission() {
        assertEquals(DownloadNetworkState.WIFI, DownloadAccess.classify(true, true, false, true, false))
        assertEquals(DownloadNetworkState.WIRED, DownloadAccess.classify(true, true, false, false, true))
        assertEquals(DownloadNetworkState.EXPENSIVE, DownloadAccess.classify(true, false, false, true, false))
        assertEquals(DownloadNetworkState.EXPENSIVE, DownloadAccess.classify(true, true, false, false, false))
        assertEquals(DownloadNetworkState.CELLULAR, DownloadAccess.classify(true, true, true, true, false))
        assertEquals(DownloadNetworkState.OFFLINE, DownloadAccess.classify(false, true, false, true, false))
    }

    @Test fun changedTransportIsRejectedUsingOriginalOperationPermission() {
        val permissionAtStart = false
        DownloadAccess.requireAllowed(DownloadNetworkState.WIFI, permissionAtStart)
        try {
            DownloadAccess.requireAllowed(DownloadNetworkState.CELLULAR, permissionAtStart)
            fail("Wi-Fi-only operation must stop after a cellular transition")
        } catch (expected: IOException) {
            assertTrue(expected.message!!.contains("Wi-Fi"))
        }
        DownloadAccess.requireAllowed(DownloadNetworkState.CELLULAR, true)
        assertTrue(DownloadNetworkState.EXPENSIVE.requiresConfirmation)
        assertFalse(DownloadNetworkState.WIFI.requiresConfirmation)
    }

    @Test fun meteredTransitionStopsRealTransferAndLaterResumeUsesThePartial() {
        val root = Files.createTempDirectory("download-access-").toFile()
        try {
            val bytes = ByteArray(32 * 1024) { it.toByte() }
            val part = PackagePart("network-policy", "model.bin", "https://fixture.invalid/model", bytes.size.toLong(),
                PackageIntegrity.hex(MessageDigest.getInstance("SHA-256").digest(bytes)))
            val file = File(root, "model.partial")
            var state = DownloadNetworkState.WIFI
            val requests = mutableListOf<Int>()
            fun connection(url: URL): HttpURLConnection {
                DownloadAccess.requireAllowed(state, false)
                return object : HttpURLConnection(url) {
                    var offset = 0
                    override fun connect() { }
                    override fun disconnect() { }
                    override fun usingProxy() = false
                    override fun getResponseCode(): Int {
                        offset = getRequestProperty("Range")?.removePrefix("bytes=")?.removeSuffix("-")?.toInt() ?: 0
                        requests += offset
                        return if (offset == 0) 200 else 206
                    }
                    override fun getHeaderField(name: String): String? = when (name) {
                        "Content-Length" -> (bytes.size - offset).toString()
                        "Content-Range" -> "bytes $offset-${bytes.size - 1}/${bytes.size}"
                        else -> null
                    }
                    override fun getInputStream() = object : InputStream() {
                        var position = offset
                        override fun read(): Int = if (position == bytes.size) -1 else bytes[position++].toInt() and 255
                        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                            if (position == bytes.size) return -1
                            val count = minOf(length, 4096, bytes.size - position)
                            bytes.copyInto(buffer, offset, position, position + count)
                            position += count
                            return count
                        }
                    }
                }
            }
            val download = ResumableDownload(openConnection = ::connection, checkNetwork = { DownloadAccess.requireAllowed(state, false) })
            try {
                download.download(part, file, {}) { state = DownloadNetworkState.CELLULAR }
                fail("A metered transition must interrupt the transfer")
            } catch (_: IOException) { }
            assertEquals(4096L, file.length())
            assertEquals(listOf(0), requests) // Retries cannot connect to the disallowed network.
            state = DownloadNetworkState.WIFI
            download.download(part, file, {}, {})
            assertEquals(listOf(0, 4096), requests)
            assertArrayEquals(bytes, file.readBytes())
        } finally { root.deleteRecursively() }
    }
}
