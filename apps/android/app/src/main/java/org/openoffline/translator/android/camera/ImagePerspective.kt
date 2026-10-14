package org.openoffline.translator.android.camera

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Explicit four-corner correction for imported/frozen photos. No automatic geometry guessing. */
object ImagePerspective {
    /** corners: normalized top-left, top-right, bottom-right, bottom-left in clockwise order. */
    fun rectify(source:Bitmap,corners:FloatArray,maxSide:Int=3072):Bitmap {
        validate(corners);require(maxSide in 32..4096)
        val points=FloatArray(8){index->corners[index]*(if(index%2==0)source.width else source.height)}
        fun edge(a:Int,b:Int)=hypot(points[a*2]-points[b*2],points[a*2+1]-points[b*2+1])
        val width=max(edge(0,1),edge(3,2));val height=max(edge(0,3),edge(1,2))
        require(width>=2 && height>=2){"Image area is too small"}
        val scale=min(1f,maxSide/max(width,height))
        val w=max(2,(width*scale).roundToInt());val h=max(2,(height*scale).roundToInt())
        val destination=floatArrayOf(0f,0f,w.toFloat(),0f,w.toFloat(),h.toFloat(),0f,h.toFloat())
        val matrix=Matrix();check(matrix.setPolyToPoly(points,0,destination,0,4)){"Invalid perspective"}
        return Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888).also{result->
            Canvas(result).apply{drawColor(Color.WHITE);drawBitmap(source,matrix,Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))}
        }
    }
    fun validate(corners:FloatArray){
        require(corners.size==8 && corners.all{it.isFinite() && it in 0f..1f}){"Choose four points within the image"}
        var area=0f
        for(i in 0..3){
            val j=(i+1)%4;val k=(i+2)%4
            val dx=corners[j*2]-corners[i*2];val dy=corners[j*2+1]-corners[i*2+1]
            val ex=corners[k*2]-corners[j*2];val ey=corners[k*2+1]-corners[j*2+1]
            require(dx*ey-dy*ex>.00001f){"Choose a convex image area in clockwise order"}
            area+=corners[i*2]*corners[j*2+1]-corners[j*2]*corners[i*2+1]
        }
        require(area/2>=.0025f){"Image area is too small"}
    }
}
