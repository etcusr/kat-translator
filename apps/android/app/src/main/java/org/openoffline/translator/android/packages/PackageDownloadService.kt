package org.openoffline.translator.android.packages

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale

/** dataSync is only active while a user-requested transfer/import/verification is running. */
class PackageDownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var repository: PackageRepository
    private lateinit var notifications: NotificationManager
    private var observer: Job? = null
    private val requested = mutableSetOf<String>()
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopping = false
    private var latestStartId = 0

    override fun onCreate() {
        super.onCreate()
        notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, text("Загрузка моделей", "Model downloads"), NotificationManager.IMPORTANCE_LOW))
        // Promote before catalog I/O or downloads, within Android's short startup deadline.
        ServiceCompat.startForeground(this, ONGOING_ID,
            NotificationCompat.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(text("Подготовка загрузки", "Preparing download")).setOngoing(true).build(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        repository = PackageDownloads.repository(this)
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Kat:PackageDownload").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopping = false
        latestStartId = startId
        val id = intent?.getStringExtra(PACKAGE_ID)
        when (intent?.action) {
            START -> if (id != null) { requested += id; repository.start(id) }
            START_BATCH -> intent.getStringArrayListExtra(PACKAGE_IDS)?.distinct()?.forEach {
                requested += it; repository.start(it)
            }
            IMPORT -> if (id != null && intent.data != null) { requested += id; repository.importFile(id, intent.data!!) }
            PAUSE_ALL -> pauseAll()
            CANCEL_ALL -> repository.cancelAll()
        }
        if (observer == null) observer = scope.launch {
            while (isActive) {
                // Poll a StateFlow snapshot: debounce/collectLatest can starve under fast downloads.
                val states = repository.states.value
                for (completed in requested.toList()) {
                    val status = states[completed] ?: continue
                    if (status.phase == PackagePhase.INSTALLED || status.phase == PackagePhase.ERROR) {
                        completion(completed, status)
                        requested.remove(completed)
                    } else if (status.phase == PackagePhase.PAUSED || status.phase == PackagePhase.ABSENT) requested.remove(completed)
                }
                val active = states.filterValues { it.busy }
                if (active.isEmpty()) finish() else notifications.notify(ONGOING_ID, ongoing(active))
                delay(500)
            }
        }
        // OS/user stop leaves verified partials; only a later explicit action resumes them.
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ dataSync budget is six hours per rolling day. Never retry around it.
        pauseAll()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        if (::repository.isInitialized) pauseAll()
        wakeLock?.let { if (it.isHeld) it.release() }
        scope.cancel()
        // The UI may still be using this process-wide repository. Never close its lock here.
        super.onDestroy()
    }

    private fun busyIds(): List<String> = repository.states.value.filterValues { it.busy }.keys.toList()
    private fun pauseAll() = busyIds().forEach(repository::pause)
    private fun finish() {
        if (stopping) return
        // A newer start command may already be queued in the system.
        if (!stopSelfResult(latestStartId)) return
        stopping = true
        wakeLock?.let { if (it.isHeld) it.release() }
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun ongoing(active: Map<String, PackageStatus>): Notification {
        val current = active.entries.firstOrNull { it.value.phase != PackagePhase.QUEUED } ?: active.entries.first()
        val item = repository.catalog.first { it.id == current.key }
        val phase = when (current.value.phase) {
            PackagePhase.QUEUED -> text("В очереди", "Queued")
            PackagePhase.VERIFYING -> text("Проверка SHA-256", "Verifying SHA-256")
            PackagePhase.INSTALLING -> text("Установка", "Installing")
            else -> "${(current.value.progress * 100).toInt()}%"
        }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle(text(item.title))
            .setContentText("$phase · ${active.size} " + text("пакет(ов)", "package(s)"))
            .setOnlyAlertOnce(true).setOngoing(true).setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openApp())
            .setProgress(1000, (current.value.progress * 1000).toInt(), current.value.phase != PackagePhase.DOWNLOADING)
            .addAction(android.R.drawable.ic_media_pause, text("Пауза", "Pause"), command(PAUSE_ALL))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, text("Отменить", "Cancel"), command(CANCEL_ALL))
            .build()
    }

    private fun completion(id: String, status: PackageStatus) {
        if (!notifications.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) return
        val pack = repository.catalog.first { it.id == id }
        val success = status.phase == PackagePhase.INSTALLED
        notifications.notify("package:$id", 1, NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(if (success) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setContentTitle(text(pack.title)).setContentText(if (success) text("Пакет проверен и установлен", "Package verified and installed")
                else text("Загрузка не завершена. Откройте приложение", "Download incomplete. Open the app"))
            .setAutoCancel(true).setContentIntent(openApp()).build())
    }

    private fun command(action: String): PendingIntent = PendingIntent.getForegroundService(this, action.hashCode(),
        Intent(this, PackageDownloadService::class.java).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun openApp(): PendingIntent? = packageManager.getLaunchIntentForPackage(packageName)?.let {
        PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun text(ru: String, en: String? = null): String {
        val preference = getSharedPreferences("kat", MODE_PRIVATE).getString("interfaceLanguage", "system")
        val locales = android.os.LocaleList.getDefault()
        val language = org.openoffline.translator.android.UiStrings.language(preference, (0 until locales.size()).map { locales[it].toLanguageTag() })
        return org.openoffline.translator.android.UiStrings.text(ru, en, language)
    }

    companion object {
        const val START = "org.openoffline.packages.START"
        const val START_BATCH = "org.openoffline.packages.START_BATCH"
        const val IMPORT = "org.openoffline.packages.IMPORT"
        const val PAUSE_ALL = "org.openoffline.packages.PAUSE_ALL"
        const val CANCEL_ALL = "org.openoffline.packages.CANCEL_ALL"
        const val PACKAGE_ID = "packageId"
        const val PACKAGE_IDS = "packageIds"
        private const val CHANNEL = "model-downloads"
        private const val ONGOING_ID = 7410
    }
}
