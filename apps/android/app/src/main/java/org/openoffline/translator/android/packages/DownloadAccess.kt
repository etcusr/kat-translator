package org.openoffline.translator.android.packages

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

enum class DownloadNetworkState {
    UNKNOWN, OFFLINE, WIFI, WIRED, CELLULAR, EXPENSIVE;
    val requiresConfirmation: Boolean get() = this != WIFI && this != WIRED
    fun canDownload(allowCellular: Boolean): Boolean = when (this) {
        UNKNOWN, OFFLINE -> false
        WIFI, WIRED -> true
        CELLULAR, EXPENSIVE -> allowCellular
    }
}

/** Permission applies to cellular and other metered/unknown transports, as on Apple. */
object DownloadAccess {
    fun allowCellular(context: Context): Boolean = context.applicationContext
        .getSharedPreferences("kat", Context.MODE_PRIVATE).getBoolean("allowCellularDownloads", false)
    fun setAllowCellular(context: Context, value: Boolean) {
        context.applicationContext.getSharedPreferences("kat", Context.MODE_PRIVATE)
            .edit().putBoolean("allowCellularDownloads", value).apply()
    }
    fun networkState(context: Context): DownloadNetworkState {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return DownloadNetworkState.UNKNOWN
        val network = manager.activeNetwork ?: return DownloadNetworkState.OFFLINE
        return classify(manager.getNetworkCapabilities(network))
    }
    fun requireNetwork(context: Context, allowCellular: Boolean = allowCellular(context)) {
        requireAllowed(networkState(context), allowCellular)
    }
    internal fun requireAllowed(state: DownloadNetworkState, allowCellular: Boolean) {
        if (!state.canDownload(allowCellular)) throw IOException(if (state == DownloadNetworkState.UNKNOWN || state == DownloadNetworkState.OFFLINE)
            "Нет подключения к интернету" else "Разрешите мобильный интернет или подключитесь к обычному Wi-Fi")
    }
    internal fun classify(capabilities: NetworkCapabilities?): DownloadNetworkState {
        if (capabilities == null) return DownloadNetworkState.UNKNOWN
        return classify(
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
        )
    }
    internal fun classify(internet: Boolean, unmetered: Boolean, cellular: Boolean, wifi: Boolean, wired: Boolean): DownloadNetworkState = when {
        !internet -> DownloadNetworkState.OFFLINE
        cellular -> DownloadNetworkState.CELLULAR
        !unmetered -> DownloadNetworkState.EXPENSIVE
        wifi -> DownloadNetworkState.WIFI // Includes VPNs whose capabilities identify unmetered Wi-Fi.
        wired -> DownloadNetworkState.WIRED
        else -> DownloadNetworkState.EXPENSIVE // A VPN with unknown underlying cost is not assumed free.
    }
    internal fun openConnection(context: Context, url: URL, allowCellular: Boolean): HttpURLConnection {
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: throw IOException("Нет подключения к интернету")
        val network = manager.activeNetwork ?: throw IOException("Нет подключения к интернету")
        requireAllowed(classify(manager.getNetworkCapabilities(network)), allowCellular)
        // Bind only this connection, never the app process. A lost Wi-Fi network cannot
        // silently switch the socket to cellular; a retry checks the new network again.
        return network.openConnection(url) as HttpURLConnection
    }
}
