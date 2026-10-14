package org.openoffline.translator.android.camera
import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
@RunWith(AndroidJUnit4::class)
class CameraPixelsDeviceTest {
    @Test fun perspectiveRectifiesChosenAreaWithoutMutatingSource(){
        val source=Bitmap.createBitmap(200,100,Bitmap.Config.ARGB_8888).apply{eraseColor(Color.BLUE)}
        for(y in 20 until 80)for(x in 40 until 160)source.setPixel(x,y,Color.RED)
        val corrected=ImagePerspective.rectify(source,floatArrayOf(.2f,.2f,.8f,.2f,.8f,.8f,.2f,.8f))
        try{assertEquals(120,corrected.width);assertEquals(60,corrected.height);assertEquals(Color.RED,corrected.getPixel(60,30));assertEquals(Color.BLUE,source.getPixel(0,0))}
        finally{corrected.recycle();source.recycle()}
    }
    @Test fun jpegDecodeBoundsMemoryAndReturnsReadablePixels(){
        val source=Bitmap.createBitmap(2000,1000,Bitmap.Config.ARGB_8888).apply{eraseColor(Color.WHITE)}
        val bytes=ByteArrayOutputStream().also{source.compress(Bitmap.CompressFormat.JPEG,95,it)}.toByteArray();source.recycle()
        val decoded=CameraPixels.jpeg(bytes,1000)
        try{assertEquals(1000,decoded.width);assertEquals(500,decoded.height);assertEquals(Color.WHITE,decoded.getPixel(500,250))}
        finally{decoded.recycle()}
    }
    @Test fun frameOwnershipReleasesExactlyOnce(){
        var releases=0
        val bitmap=Bitmap.createBitmap(2,2,Bitmap.Config.ARGB_8888)
        val frame=CameraFrame(bitmap,7){releases++};frame.close();frame.close()
        assertEquals(1,releases);assertTrue(bitmap.isRecycled);assertEquals(7L,frame.revision)
    }
}
