package org.openoffline.translator.android

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageDownloadService
import org.openoffline.translator.android.packages.PackageDownloads
import org.openoffline.translator.android.packages.PackagePhase

/** Device lifecycle checks use an already installed OCR file: no Index/network transfer. */
@RunWith(AndroidJUnit4::class)
class PackageDownloadServiceTest {
    @get:Rule val environment=UiTestEnvironment.wrap()
    @Test fun cachedPackageNotifiesAndIdlePauseCancelStopWithoutTouchingModel() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val context = inst.targetContext
        val id = InstrumentationRegistry.getArguments().getString("servicePackageId", "ppocr-v5-english")!!
        require(id in setOf("ppocr-v5-english", "ppocr-v5-eslav", "ppocr-v5-det"))
        fun stage(message: String) = inst.sendStatus(0, Bundle().apply { putString("stream", "\nDownload service: $message\n") })
        fun await(message: String, check: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + 30_000
            while (!check() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(25)
            assertTrue(message, check())
        }
        val activity = inst.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val notifications = context.getSystemService(NotificationManager::class.java)
        val manager = context.getSystemService(ActivityManager::class.java)
        @Suppress("DEPRECATION")
        fun running(): Boolean = manager.getRunningServices(100).any { it.service.className == PackageDownloadService::class.java.name }
        try {
            stage("wait for existing OCR package and idle repository")
            val repository = PackageDownloads.repository(context)
            assertSame(repository, PackageDownloads.repository(context.applicationContext))
            await("Install the OCR fixture before this test") { repository.states.value[id]?.phase == PackagePhase.INSTALLED }
            await("Other package work must finish before this lifecycle test") { repository.states.value.values.none { it.busy } }
            val model = requireNotNull(repository.installedPath(id))
            val size = model.length()
            val modified = model.lastModified()
            // Permission changes belong to the external harness: revoke kills this process.
            assertTrue("Grant POST_NOTIFICATIONS before this test; the host harness must restore its original state afterward",
                Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            assertTrue("Enable notifications before the completion-notification test", notifications.areNotificationsEnabled())
            notifications.cancel("package:$id", 1)
            stage("start foreground service for the already verified file")
            inst.runOnMainSync { PackageDownloads.start(context, id) }
            await("Verified completion notification not delivered") {
                notifications.activeNotifications.any { it.tag == "package:$id" }
            }
            await("Completed foreground service did not stop") { !running() }
            assertEquals(size, model.length())
            assertEquals("Already installed package must not be downloaded or replaced", modified, model.lastModified())
            assertEquals(PackagePhase.INSTALLED, repository.states.value[id]?.phase)

            stage("notification pause/cancel commands are safe with an idle repository")
            for (action in listOf(PackageDownloadService.PAUSE_ALL, PackageDownloadService.CANCEL_ALL)) {
                inst.runOnMainSync { ContextCompat.startForegroundService(context, Intent(context, PackageDownloadService::class.java).setAction(action)) }
                // Synchronize the service-start IPC, then verify it drains promptly without work.
                inst.waitForIdleSync()
                await("Idle command did not stop the service") { !running() }
                assertEquals(size, model.length())
                assertEquals(modified, model.lastModified())
                assertEquals(PackagePhase.INSTALLED, repository.states.value[id]?.phase)
            }
            stage("pass: singleton, verified completion notification, stop, safe idle actions; no network transfer")
        } finally {
            notifications.cancel("package:$id", 1)
            inst.runOnMainSync { activity.finish() }
        }
    }
}
