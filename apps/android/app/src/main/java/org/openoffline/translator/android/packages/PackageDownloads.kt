package org.openoffline.translator.android.packages

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat

/** Process-wide owner shared by UI and service: never opens a second repository lock. */
object PackageDownloads {
    @Volatile private var instance: PackageRepository? = null

    fun repository(context: Context): PackageRepository = instance ?: synchronized(this) {
        instance ?: PackageRepository(context.applicationContext).also { instance = it }
    }

    /** Call from a visible Activity/user action, as required by Android 12+ FGS rules. */
    fun start(context: Context, id: String) = launch(context, PackageDownloadService.START, id)
    fun importFile(context: Context, id: String, uri: Uri) = launch(context, PackageDownloadService.IMPORT, id, uri)
    fun pause(context: Context, id: String) { repository(context).pause(id) }
    fun cancel(context: Context, id: String) { repository(context).cancel(id) }
    fun remove(context: Context, id: String) { repository(context).remove(id) }
    fun pauseAll(context: Context) { repository(context).pauseAll() }
    fun cancelAll(context: Context) { repository(context).cancelAll() }
    fun startAll(context: Context, ids: Collection<String>) {
        val unique = ids.distinct()
        if (unique.isEmpty()) return
        val repository = repository(context)
        require(unique.all { id -> repository.catalog.any { it.id == id && it.unavailableReason == null } }) { "Package is unavailable" }
        if (repository.maximumDownloadBytes(unique) > 0) DownloadAccess.requireNetwork(context)
        repository.checkSpace(unique)
        ContextCompat.startForegroundService(context, Intent(context, PackageDownloadService::class.java)
            .setAction(PackageDownloadService.START_BATCH)
            .putStringArrayListExtra(PackageDownloadService.PACKAGE_IDS, ArrayList(unique)))
    }

    private fun launch(context: Context, action: String, id: String, uri: Uri? = null) {
        val repository = repository(context)
        require(repository.catalog.any { it.id == id && it.unavailableReason == null }) { "Package is unavailable" }
        if (action == PackageDownloadService.START && repository.maximumDownloadBytes(listOf(id)) > 0) DownloadAccess.requireNetwork(context)
        ContextCompat.startForegroundService(context, Intent(context, PackageDownloadService::class.java).apply {
            this.action = action
            putExtra(PackageDownloadService.PACKAGE_ID, id)
            data = uri
            if (uri != null) addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}
