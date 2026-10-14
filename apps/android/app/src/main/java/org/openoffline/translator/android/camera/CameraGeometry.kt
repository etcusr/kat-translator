package org.openoffline.translator.android.camera

import kotlin.math.max

/** Pure geometry shared by preview, OCR frames, focus, and device tests. Rear camera only. */
object CameraGeometry {
    fun rotation(sensor:Int,displayDegrees:Int):Int {
        require(sensor%90==0 && displayDegrees%90==0)
        return ((sensor-displayDegrees)%360+360)%360
    }
    /** Raw sensor coordinates, normalized, mapped clockwise into upright frame coordinates. */
    fun upright(x:Float,y:Float,rotation:Int):Pair<Float,Float> = when(rotation) {
        0->x to y;90->1f-y to x;180->1f-x to 1f-y;270->y to 1f-x
        else->throw IllegalArgumentException("Expected right-angle rotation")
    }
    fun sensor(x:Float,y:Float,rotation:Int):Pair<Float,Float> = upright(x,y,(360-rotation)%360)
    /** Undoes the preview's centered fill crop before mapping a tap to the sensor. */
    fun focus(x:Float,y:Float,viewWidth:Int,viewHeight:Int,bufferWidth:Int,bufferHeight:Int,rotation:Int):Pair<Float,Float> {
        require(viewWidth>0 && viewHeight>0 && bufferWidth>0 && bufferHeight>0)
        val w=if(rotation%180==0)bufferWidth else bufferHeight
        val h=if(rotation%180==0)bufferHeight else bufferWidth
        val scale=max(viewWidth.toFloat()/w,viewHeight.toFloat()/h)
        val u=((x.coerceIn(0f,1f)*viewWidth+(w*scale-viewWidth)/2)/(w*scale)).coerceIn(0f,1f)
        val v=((y.coerceIn(0f,1f)*viewHeight+(h*scale-viewHeight)/2)/(h*scale)).coerceIn(0f,1f)
        return sensor(u,v,rotation)
    }
}
