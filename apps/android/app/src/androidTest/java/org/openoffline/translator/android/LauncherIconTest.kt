package org.openoffline.translator.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.AdaptiveIconDrawable
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class LauncherIconTest {
    @Test fun launcherUsesBlackAdaptiveBackgroundAndLimeMark() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val icon=context.applicationInfo.loadIcon(context.packageManager)
        assertTrue("Launcher must not wrap a legacy square PNG in white",icon is AdaptiveIconDrawable)
        val adaptive=icon as AdaptiveIconDrawable
        val background=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888)
        try {
            adaptive.background.setBounds(0,0,256,256)
            adaptive.background.draw(Canvas(background))
            for(x in listOf(0,128,255))for(y in listOf(0,128,255))assertEquals(Color.BLACK,background.getPixel(x,y))
            background.eraseColor(Color.TRANSPARENT)
            icon.setBounds(0,0,256,256);icon.draw(Canvas(background))
            val pixels=IntArray(256*256);background.getPixels(pixels,0,256,0,0,256,256)
            assertTrue("Original lime brand color must be visible",pixels.count { it==Color.rgb(198,244,50) }>1000)
            assertFalse("No white launcher backing",pixels.any { Color.alpha(it)>200 && Color.red(it)>245 && Color.green(it)>245 && Color.blue(it)>245 })
            File(context.getExternalFilesDir(null),"ui-launcher-icon.png").outputStream().use { background.compress(Bitmap.CompressFormat.PNG,100,it) }
        } finally { background.recycle() }
    }
}
