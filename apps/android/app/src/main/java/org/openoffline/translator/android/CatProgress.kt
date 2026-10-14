package org.openoffline.translator.android

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import kotlin.math.*

/** Neon geometry/palette from shared/apple/Shared/CatProgressDrawing.swift.
 * The character is decorative. Only a real fraction is exposed as percentage. */
@Composable internal fun CatProgress(progress:Float?=null,modifier:Modifier=Modifier,prominent:Boolean=false) {
    val lifecycle=androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) }
    var enabled by remember { mutableStateOf(android.animation.ValueAnimator.areAnimatorsEnabled()) }
    DisposableEffect(lifecycle) {
        val observer=androidx.lifecycle.LifecycleEventObserver { _,event ->
            if(event==androidx.lifecycle.Lifecycle.Event.ON_START) { active=true;enabled=android.animation.ValueAnimator.areAnimatorsEnabled() }
            if(event==androidx.lifecycle.Lifecycle.Event.ON_STOP)active=false
        }
        lifecycle.addObserver(observer);onDispose { lifecycle.removeObserver(observer) }
    }
    val time=if(active && enabled) {
        val elapsed by rememberInfiniteTransition(label="cat.progress").animateFloat(
            initialValue=0f,targetValue=86_400f,
            animationSpec=infiniteRepeatable(tween(86_400_000,easing=LinearEasing)),label="cat.clock")
        elapsed
    } else 0f
    val fraction=progress?.takeIf { it.isFinite() }?.coerceIn(0f,1f)
    val preparation=remember { CatPreparation() }
    val download=remember { CatMotion(fraction?.toDouble() ?: 0.0,0.0) }
    Canvas(modifier.fillMaxWidth().height(if(prominent)190.dp else 62.dp).semantics {
        progressBarRangeInfo=if(fraction==null)ProgressBarRangeInfo.Indeterminate else ProgressBarRangeInfo(fraction,0f..1f)
    }) {
        val width=if(prominent)minOf(160.dp.toPx(),maxOf(72.dp.toPx(),size.width*.28f)) else 68.dp.toPx()
        val height=width*.8f
        if(fraction==null && active && enabled)preparation.advance(time.toDouble(),(width/(size.width-width).coerceAtLeast(1f)).toDouble())
        if(fraction!=null)download.advance(fraction.toDouble(),active && enabled,time.toDouble())
        val position=(fraction?.let { download.position } ?: preparation.position).toFloat()
        val motion=if(!active || !enabled)CatMotion(position.toDouble(),time.toDouble()) else if(fraction==null)preparation.motion else download
        val play=if(fraction==null && active && enabled)preparation.play else CatPlay(time.toDouble())
        val trackHeight=(if(prominent)(width/20).coerceIn(4.dp.toPx(),8.dp.toPx()) else 4.dp.toPx());val trackY=size.height-trackHeight
        drawRoundRect(Color.White.copy(alpha=.12f),Offset(0f,trackY),Size(size.width,trackHeight),androidx.compose.ui.geometry.CornerRadius(trackHeight))
        val fillWidth=size.width*(fraction ?: .22f)
        drawRoundRect(KatAccent,Offset(if(fraction==null)(size.width-fillWidth)*position else 0f,trackY),Size(fillWidth,trackHeight),androidx.compose.ui.geometry.CornerRadius(trackHeight))
        play.markPosition?.let { mark ->
            val mx=(size.width-width)*mark.toFloat()+width*(if(play.markKind==CatPlay.Mark.PILE) { if(play.markFacingRight).16f else .56f } else if(play.markFacingRight).74f else -.02f)
            val cover=play.markCover.toFloat();val alpha=play.markOpacity.toFloat()
            if(play.markKind==CatPlay.Mark.PILE) {
                val h=width*.13f*(1-cover*.85f)
                drawPath(Path().apply { moveTo(mx,trackY-5);quadraticTo(mx-width*.05f,trackY-h*.45f,mx+width*.08f,trackY-h*.55f);quadraticTo(mx+width*.14f,trackY-h,mx+width*.1f,trackY-h);quadraticTo(mx+width*.24f,trackY-h*.6f,mx+width*.22f,trackY-5);close() },KatAccent.copy(alpha=alpha*(1-cover)*.8f))
            } else { drawOval(KatAccent.copy(alpha=alpha*.7f),Offset(mx,trackY-8),Size(width*.28f,5.dp.toPx()));drawOval(KatAccent.copy(alpha=alpha*.5f),Offset(mx+width*.2f,trackY-12),Size(5.dp.toPx(),3.dp.toPx())) }
        }
        translate((size.width-width).coerceAtLeast(0f)*position,trackY-height-5.dp.toPx()) {
            scale(width/80f,height/64f,Offset.Zero) { neonCat(motion,play,fraction!=null || preparation.facingRight) }
        }
    }
}
private fun DrawScope.neonCat(motion:CatMotion,play:CatPlay,facingRight:Boolean) {
    val playfulLeap=play.leap.toFloat();val digging=play.digging.toFloat();val retching=play.retching.toFloat();val crouch=play.crouch.toFloat();val heave=play.heave.toFloat()
    val wallSpring=play.trick==CatPlay.Trick.WALL_KICK;val preserve=play.trick==CatPlay.Trick.MISCHIEF
    val standing=maxOf(motion.standing.toFloat(),if(digging>0 || wallSpring)1f else maxOf(retching*.95f,playfulLeap))
    val natural=if(preserve || digging>0)0f else standing
    val tuck=if(preserve)0f else maxOf(playfulLeap,motion.leap.toFloat())*natural
    val coil=if(wallSpring)crouch else 0f;val twist=sin(PI.toFloat()*play.turn.toFloat());val time=motion.animationTime.toFloat()
    val gait=if(digging>0 || retching>0 || crouch>0 || wallSpring || tuck>.1f)0f else motion.stride.toFloat()*standing
    fun kick(phase:Float)=maxOf(0f,sin(digging*PI.toFloat()*8+phase))*(if(digging>0)1 else 0)
    fun mix(a:Float,b:Float)=a+(b-a)*standing
    fun path(vararg values:Float):Path=Path().apply { moveTo(values[0],values[1]);for(i in 2 until values.size step 2)lineTo(values[i],values[i+1]) }
    fun line(p:Path,opacity:Float=1f,width:Float=2.6f)=drawPath(p,KatAccent.copy(alpha=opacity),style=Stroke(width,cap=StrokeCap.Round,join=StrokeJoin.Round))
    fun outlined(p:Path) { drawPath(p,Color(0xFF1B1729));line(p) }
    withTransform({
        if(!facingRight) { translate(80f,0f);scale(-1f,1f,Offset.Zero) }
        val bounce=if(motion.phase==CatMotion.Phase.WALKING)abs(gait)*(.6f+motion.running.toFloat()) else 0f
        translate(0f,-bounce-motion.leap.toFloat()*8)
        translate(0f,-playfulLeap*30);rotate(play.rotation.toFloat(),Offset(40f,32f))
        scale(1f,1-(if(retching>0)0f else crouch)*.16f,Offset(0f,58f))
    }) {
        line(Path().apply { moveTo(mix(34f,24f),44f);cubicTo(7f,61f-natural*18-tuck*5,4f,40f-tuck*7,11f+sin(time*1.6f)*2,mix(34f,24f)+natural*6-tuck*10) },width=3f)
        for((hip,foot,phase) in listOf(Triple(mix(34f,25f),mix(32f,21f),-1f),Triple(51f,50f,1f))) {
            val rear=phase<0;val sweep=if(rear)kick(PI.toFloat()) else 0f
            val fx=foot+gait*6*phase+(if(rear)9 else -7)*tuck+(if(rear)4 else -2)*coil;val fy=54-tuck*9-maxOf(0f,gait*phase)*3
            if(natural>0)line(path(hip,41f,if(rear)hip+5 else hip-2,48-tuck*5,fx,fy,fx+4,fy),.65f)
            else line(path(hip,41f,foot+gait*6*phase-sweep*16,54-sweep*5,foot+gait*6*phase+4-sweep*16,54-sweep*5),.78f)
        }
        val body=Path()
        if(natural>.05f) { val rear=mix(29f,20f);val shoulder=mix(54f,58f);val arch=heave*7+tuck*2;body.moveTo(rear,42f);body.cubicTo(rear-2,27-arch,43f,28-arch,shoulder,34+heave*2);body.quadraticTo(shoulder+5,41f,shoulder-2,49f);body.cubicTo(42f,45-heave*3,rear+2,57-tuck*4,rear,42f);body.close() }
        else { val x=mix(29f,20f);val y=mix(29f,32f);body.addOval(androidx.compose.ui.geometry.Rect(x,y,x+mix(29f,39f),y+mix(29f,19f))) }
        outlined(body)
        for((hip,foot,phase) in listOf(Triple(mix(42f,30f),mix(43f,31f),1f),Triple(56f,59f,-1f))) {
            val rear=phase>0;val sweep=if(rear)kick(0f) else 0f
            val lift=motion.leap.toFloat()*4+playfulLeap*6+maxOf(0f,gait*phase)*2+sweep*7
            val fx=foot+gait*6*phase+(if(rear)9 else -10)*tuck+(if(rear)4 else -3)*coil;val fy=58-lift-tuck*6
            if(natural>0)line(path(hip,43f,if(rear)hip+5 else hip-2,50-tuck*5,fx,fy,fx+5,fy))
            else line(path(hip,43f,foot+gait*6*phase-sweep*20,58-lift,foot+gait*6*phase+5-sweep*20,58-lift))
        }
        if(digging>0)for(i in 0 until 5) { val phase=(digging*4+i*.19f)%1;drawOval(KatAccent.copy(alpha=(1-phase)*.7f),Offset(24-phase*22,58-sin(phase*PI.toFloat())*(7+i%2*4)),Size(2.4f,1.8f)) }
        val x=mix(44f,52f)+retching*3+heave*3-twist*16;val y=mix(21f,26f)+retching*12+heave*3-tuck*2
        scale(1-natural*.23f,1-natural*.23f,Offset(x+4,y+5)) {
            outlined(Path().apply {
                moveTo(x-12,y-2);lineTo(x-10,y-17);quadraticTo(x-9,y-20,x-6,y-17)
                lineTo(x,y-10);lineTo(x+8,y-10);lineTo(x+13,y-17);quadraticTo(x+16,y-20,x+17,y-16)
                lineTo(x+21,y-2);quadraticTo(x+25,y+13,x+12,y+14);lineTo(x-2,y+14);quadraticTo(x-17,y+13,x-12,y-2);close()
            })
            for(eye in listOf(x-3,x+10))drawOval(KatAccent,Offset(eye,y+1),Size(3.8f,if(time%4.6f>4.35f || retching>.2f)1f else 5.5f))
            if(retching>.2f) {
                drawOval(KatAccent,Offset(x+4,y+9),Size(5f,4f),style=Stroke(1.6f))
                if(play.spill>0)line(Path().apply { moveTo(x+7,y+13);quadraticTo(75f,49f,70f,62f) },play.spill.toFloat()*.85f,2.5f)
            } else line(path(x+3,y+9,x+5,y+10,x+7,y+9),width=1.6f)
        }
    }
}
