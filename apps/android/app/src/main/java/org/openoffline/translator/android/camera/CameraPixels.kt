package org.openoffline.translator.android.camera

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.media.Image
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object CameraPixels {
    /** YUV_420_888 planes may have independent row/pixel strides and nonzero positions. */
    fun yuv(image:Image,rotation:Int,maxSide:Int=1600):Bitmap {
        require(image.format==ImageFormat.YUV_420_888 && image.planes.size==3)
        val crop=image.cropRect
        require(crop.width()>0 && crop.height()>0 && maxSide in 32..3072)
        val scale=min(1f,maxSide.toFloat()/max(crop.width(),crop.height()))
        val w=max(1,(crop.width()*scale).roundToInt());val h=max(1,(crop.height()*scale).roundToInt())
        val planes=image.planes
        val buffers=planes.map{it.buffer.duplicate()}
        val starts=buffers.map{it.position()}
        fun component(plane:Int,x:Int,y:Int):Int {
            val index=starts[plane]+y*planes[plane].rowStride+x*planes[plane].pixelStride
            return buffers[plane].get(index).toInt() and 255
        }
        val pixels=IntArray(w*h)
        for(y in 0 until h)for(x in 0 until w){
            val sx=crop.left+min(crop.width()-1,(x/scale).toInt())
            val sy=crop.top+min(crop.height()-1,(y/scale).toInt())
            pixels[y*w+x]=yuvColor(component(0,sx,sy),component(1,sx/2,sy/2),component(2,sx/2,sy/2))
        }
        val bitmap=Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888)
        if(rotation==0)return bitmap
        return Bitmap.createBitmap(bitmap,0,0,w,h,Matrix().apply{postRotate(rotation.toFloat())},true).also{if(it!==bitmap)bitmap.recycle()}
    }
    /** Limited-range BT.601 conversion used by Android camera YUV output. */
    fun yuvColor(y:Int,u:Int,v:Int):Int {
        val c=max(0,y-16);val d=u-128;val e=v-128
        val r=((298*c+409*e+128) shr 8).coerceIn(0,255)
        val g=((298*c-100*d-208*e+128) shr 8).coerceIn(0,255)
        val b=((298*c+516*d+128) shr 8).coerceIn(0,255)
        return (255 shl 24) or (r shl 16) or (g shl 8) or b
    }
    /** ImageDecoder applies camera JPEG EXIF orientation exactly once. */
    fun jpeg(bytes:ByteArray,maxSide:Int=3072):Bitmap {
        require(bytes.isNotEmpty() && maxSide in 32..4096)
        return ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(bytes))){decoder,info,_->
            decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE
            val scale=min(1f,maxSide.toFloat()/max(info.size.width,info.size.height))
            decoder.setTargetSize(max(1,(info.size.width*scale).roundToInt()),max(1,(info.size.height*scale).roundToInt()))
        }
    }
}
