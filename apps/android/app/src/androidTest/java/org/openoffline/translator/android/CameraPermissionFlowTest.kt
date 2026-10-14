package org.openoffline.translator.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Starts with CAMERA revoked + request flags cleared by the host. Denies once,
 * verifies useful retry, grants through Android's real dialog, then leaves camera.
 * Host restores the original permission after instrumentation exits. */
@RunWith(AndroidJUnit4::class)
class CameraPermissionFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    @Test fun enteringCameraRequestsAccessAndDenialCanBeRetried() {
        val inst=InstrumentationRegistry.getInstrumentation();val ctx=inst.targetContext
        val serviceInfo=inst.uiAutomation.serviceInfo
        serviceInfo.flags=serviceInfo.flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        inst.uiAutomation.serviceInfo=serviceInfo
        assertEquals(PackageManager.PERMISSION_DENIED,ctx.checkSelfPermission(Manifest.permission.CAMERA))
        val prefs=ctx.getSharedPreferences("kat-permissions",0)
        val existed=prefs.contains(Manifest.permission.CAMERA);val old=prefs.getBoolean(Manifest.permission.CAMERA,false)
        lateinit var state:TranslatorState
        fun button(id:String):AccessibilityNodeInfo {
            val deadline=SystemClock.elapsedRealtime()+8_000
            do {
                inst.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByViewId("com.android.permissioncontroller:id/$id")?.firstOrNull()?.let { return it }
                Thread.sleep(80)
            } while(SystemClock.elapsedRealtime()<deadline)
            throw AssertionError("Android permission button missing: $id; root=${inst.uiAutomation.rootInActiveWindow}")
        }
        try {
            ui.runOnIdle { state=ViewModelProvider(ui.activity)[TranslatorState::class.java];state.setHistory(false);state.changeRecordImages(false);state.mode="camera" }
            ui.waitForIdle()
            assertTrue(button("permission_deny_button").performAction(AccessibilityNodeInfo.ACTION_CLICK))
            ui.onNodeWithTag("camera.permission").assertIsDisplayed().performClick()
            assertTrue(button("permission_allow_foreground_only_button").performAction(AccessibilityNodeInfo.ACTION_CLICK))
            ui.waitUntil(5_000) { ctx.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED }
            ui.onNodeWithTag("camera.permission").assertDoesNotExist()
            ui.runOnIdle { state.stopLiveCamera();state.mode="voice" }
        } finally {
            ui.runOnIdle { state.stopLiveCamera();state.mode="voice" }
            val edit=prefs.edit();if(existed)edit.putBoolean(Manifest.permission.CAMERA,old) else edit.remove(Manifest.permission.CAMERA);assertTrue(edit.commit())
        }
    }
}
