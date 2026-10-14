package org.openoffline.translator.android

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.dp
import kotlin.math.*

/** Platform-neutral outline glyphs; sizes and placement follow the SwiftUI controls. */
@Composable fun KatIcon(name: String, color: Color=KatAccent, modifier: Modifier=Modifier) {
    Canvas(modifier.size(22.dp)) {
        scale(size.width/24f, size.height/24f, pivot=Offset.Zero) {
            val stroke=Stroke(1.65f,cap=StrokeCap.Round)
            fun line(x:Float,y:Float,x2:Float,y2:Float) = drawLine(color,Offset(x,y),Offset(x2,y2),1.65f,StrokeCap.Round)
            fun path(vararg p:Float) { val path=Path(); path.moveTo(p[0],p[1]); for(i in 2 until p.size step 2)path.lineTo(p[i],p[i+1]); drawPath(path,color,style=stroke) }
            when(name) {
                "history" -> { drawCircle(color,9f,Offset(12f,12f),style=stroke); path(12f,6f,12f,12f,16f,12f) }
                "settings" -> { drawCircle(color,4f,Offset(12f,12f),style=stroke); drawCircle(color,8f,Offset(12f,12f),style=stroke); for(i in 0..7) { val a=i*PI/4;line((12+8*cos(a)).toFloat(),(12+8*sin(a)).toFloat(),(12+11*cos(a)).toFloat(),(12+11*sin(a)).toFloat()) } }
                "models" -> { path(2f,7f,12f,2f,22f,7f,12f,12f,2f,7f); path(2f,12f,12f,17f,22f,12f); path(2f,17f,12f,22f,22f,17f) }
                "swap" -> { path(7f,3f,2f,8f,21f,8f); path(17f,21f,22f,16f,3f,16f) }
                "down" -> path(6f,9f,12f,15f,18f,9f)
                "next" -> path(9f,5f,16f,12f,9f,19f)
                "back" -> path(15f,5f,8f,12f,15f,19f)
                "close" -> { line(5f,5f,19f,19f);line(19f,5f,5f,19f) }
                "clear" -> { drawCircle(color.copy(alpha=.25f),10f,Offset(12f,12f));line(8f,8f,16f,16f);line(16f,8f,8f,16f) }
                "copy" -> { drawRoundRect(color,Offset(8f,7f),Size(12f,15f),androidx.compose.ui.geometry.CornerRadius(2f),style=stroke);path(15f,4f,15f,2f,3f,2f,3f,17f,5f,17f) }
                "expand" -> { path(3f,9f,3f,3f,9f,3f);path(15f,21f,21f,21f,21f,15f);line(3f,3f,10f,10f);line(21f,21f,14f,14f) }
                "share" -> { path(7f,9f,3f,9f,3f,22f,21f,22f,21f,9f,17f,9f);path(7f,6f,12f,1f,17f,6f);line(12f,1f,12f,15f) }
                "speaker" -> { path(3f,9f,7f,9f,12f,4f,12f,20f,7f,15f,3f,15f,3f,9f);drawArc(color,-60f,120f,false,Offset(10f,5f),Size(10f,14f),style=stroke);drawArc(color,-60f,120f,false,Offset(8f,1f),Size(16f,22f),style=stroke) }
                "mic" -> { drawRoundRect(color,Offset(8f,2f),Size(8f,13f),androidx.compose.ui.geometry.CornerRadius(4f));drawArc(color,0f,180f,false,Offset(5f,6f),Size(14f,13f),style=stroke);line(5f,11f,5f,12.5f);line(19f,11f,19f,12.5f);line(12f,19f,12f,23f);line(8f,23f,16f,23f) }
                "globe" -> { drawCircle(color,10f,Offset(12f,12f),style=stroke);drawOval(color,Offset(7f,2f),Size(10f,20f),style=stroke);line(2f,12f,22f,12f) }
                "search" -> { drawCircle(color,7f,Offset(10f,10f),style=stroke);line(15f,15f,22f,22f) }
                "check" -> path(3f,12f,9f,18f,21f,5f)
                "trash" -> { path(5f,7f,6f,22f,18f,22f,19f,7f);line(3f,5f,21f,5f);path(8f,5f,8f,2f,16f,2f,16f,5f);line(10f,10f,10f,18f);line(14f,10f,14f,18f) }
                "image" -> { drawRoundRect(color,Offset(2f,3f),Size(20f,18f),androidx.compose.ui.geometry.CornerRadius(2f),style=stroke);path(2f,18f,9f,11f,14f,16f,17f,13f,22f,18f);drawCircle(color,2f,Offset(16f,8f)) }
                "chart" -> { line(2f,22f,22f,22f); for(i in 0..2)drawRoundRect(color,Offset(4f+i*6f,12f-i*5f),Size(3f,8f+i*5f),androidx.compose.ui.geometry.CornerRadius(1f)) }
                "keyboard" -> { drawRoundRect(color,Offset(1f,3f),Size(22f,13f),androidx.compose.ui.geometry.CornerRadius(2f),style=stroke);path(8f,20f,12f,23f,16f,20f);line(6f,12f,18f,12f) }
                else -> { drawCircle(color,9f,Offset(12f,12f),style=stroke);line(12f,11f,12f,17f);drawCircle(color,1f,Offset(12f,7f)) }
            }
        }
    }
}
