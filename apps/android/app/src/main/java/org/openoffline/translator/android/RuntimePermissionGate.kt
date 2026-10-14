package org.openoffline.translator.android

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

internal data class RuntimePermissionGate(val granted:Boolean,val asked:Boolean,val settingsRequired:Boolean,val request:()->Unit)

/** Request only for an action that needs access. Returning from Android settings
 * refreshes access but never starts a microphone recording on its own. */
@Composable internal fun rememberRuntimePermission(permission:String,onGranted:()->Unit={}):RuntimePermissionGate {
    val context=LocalContext.current
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    val prefs=remember(context) { context.getSharedPreferences("kat-permissions",0) }
    fun grantedNow()=context.checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED
    var granted by remember { mutableStateOf(grantedNow()) }
    var asked by rememberSaveable(permission) { mutableStateOf(prefs.getBoolean(permission,false)) }
    var revision by remember { mutableIntStateOf(0) }
    val callback by rememberUpdatedState(onGranted)
    var activityContext:Context=context
    while(activityContext is ContextWrapper && activityContext !is Activity)activityContext=activityContext.baseContext
    val activity=activityContext as? Activity
    val launcher=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted=it;revision++;if(it)callback()
    }
    DisposableEffect(lifecycle,permission) {
        val observer=LifecycleEventObserver { _,event -> if(event==Lifecycle.Event.ON_RESUME) { granted=grantedNow();revision++ } }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    revision
    val settingsRequired=!granted && asked && activity?.shouldShowRequestPermissionRationale(permission)==false
    return RuntimePermissionGate(granted,asked,settingsRequired) {
        if(grantedNow()) { granted=true;callback() }
        else if(settingsRequired)context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:${context.packageName}")))
        else { asked=true;prefs.edit().putBoolean(permission,true).apply();launcher.launch(permission) }
    }
}
