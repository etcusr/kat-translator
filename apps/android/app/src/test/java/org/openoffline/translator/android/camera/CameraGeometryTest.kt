package org.openoffline.translator.android.camera
import org.junit.Assert.*
import org.junit.Test
class CameraGeometryTest {
    @Test fun sensorRotationAccountsForEveryDisplayOrientation(){
        assertEquals(listOf(90,0,270,180),listOf(0,90,180,270).map{CameraGeometry.rotation(90,it)})
        assertEquals(listOf(270,180,90,0),listOf(0,90,180,270).map{CameraGeometry.rotation(270,it)})
    }
    @Test fun uprightCoordinatesHaveAnExactInverse(){
        for(rotation in listOf(0,90,180,270)){
            val p=CameraGeometry.upright(.2f,.7f,rotation);val raw=CameraGeometry.sensor(p.first,p.second,rotation)
            assertEquals(.2f,raw.first,.00001f);assertEquals(.7f,raw.second,.00001f)
        }
        assertEquals(1f to 0f,CameraGeometry.upright(0f,0f,90))
    }
    @Test fun focusUndoesPreviewFillCrop(){
        // A square view displays only the central half of a 2:1 buffer.
        val left=CameraGeometry.focus(0f,.5f,100,100,200,100,0)
        val right=CameraGeometry.focus(1f,.5f,100,100,200,100,0)
        assertEquals(.25f,left.first,.00001f);assertEquals(.75f,right.first,.00001f)
        val center=CameraGeometry.focus(.5f,.5f,900,1600,1280,720,90)
        assertEquals(.5f,center.first,.00001f);assertEquals(.5f,center.second,.00001f)
    }
    @Test fun perspectiveRejectsCrossedAndDegenerateCorners(){
        ImagePerspective.validate(floatArrayOf(.1f,.1f,.9f,.2f,.8f,.9f,.2f,.8f))
        assertThrows(IllegalArgumentException::class.java){ImagePerspective.validate(floatArrayOf(0f,0f,1f,1f,1f,0f,0f,1f))}
        assertThrows(IllegalArgumentException::class.java){ImagePerspective.validate(floatArrayOf(0f,0f,0f,0f,0f,0f,0f,0f))}
        assertThrows(IllegalArgumentException::class.java){ImagePerspective.validate(floatArrayOf(Float.NaN,0f,1f,0f,1f,1f,0f,1f))}
    }
    @Test fun cameraYuvConversionUsesAllThreeComponents(){
        assertEquals(0xff000000.toInt(),CameraPixels.yuvColor(16,128,128))
        assertEquals(0xffffffff.toInt(),CameraPixels.yuvColor(235,128,128))
        val red=CameraPixels.yuvColor(81,90,240)
        assertTrue((red ushr 16 and 255)>=250);assertTrue((red ushr 8 and 255)<=3);assertTrue((red and 255)<=3)
    }
}
