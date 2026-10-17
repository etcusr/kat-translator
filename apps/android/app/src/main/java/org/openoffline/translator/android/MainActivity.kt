package org.openoffline.translator.android

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModelProvider

class MainActivity : ComponentActivity() {
    private lateinit var translator: TranslatorState
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(SystemBarStyle.dark(android.graphics.Color.BLACK), SystemBarStyle.dark(android.graphics.Color.BLACK))
        translator = ViewModelProvider(this)[TranslatorState::class.java]
        setContent { KatApp(translator) { busy ->
            if (busy) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } }
    }
    override fun onStart() { super.onStart();translator.foreground() }
    override fun onTrimMemory(level:Int) {
        super.onTrimMemory(level)
        if(level>=android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW && ::translator.isInitialized)translator.trimMemory()
    }
    override fun onLowMemory() { super.onLowMemory();if(::translator.isInitialized)translator.trimMemory() }
    override fun onStop() {
        if (!isChangingConfigurations) translator.background()
        super.onStop()
    }
}
