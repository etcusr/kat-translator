package org.openoffline.translator.android

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.viewinterop.AndroidView
import org.json.JSONArray

private object AnimationLibrary {
    private var deck:LoadingAnimationDeck?=null
    @Synchronized fun deck(context:Context):LoadingAnimationDeck {
        return deck ?: run {
            val assets=context.assets.list("").orEmpty().toSet()
            val rows=JSONArray(context.assets.open("loading-animations.json").bufferedReader().use { it.readText() })
            LoadingAnimationDeck((0 until rows.length()).map { rows.getJSONObject(it) }
                .filter { it.optDouble("duration",0.0)>0 && "${it.getString("resource")}.mp4" in assets }
                .map { it.getString("resource") }).also { deck=it }
        }
    }
}

@Composable internal fun WizardVideo(modifier:Modifier=Modifier) {
    val context=LocalContext.current
    val deck=remember { AnimationLibrary.deck(context) }
    var player:MediaPlayer? by remember { mutableStateOf(null) }
    var outputSurface:Surface? by remember { mutableStateOf(null) }
    var resource by remember { mutableStateOf("") }
    val lifecycle=androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var foreground by remember { mutableStateOf(lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) }
    var animationsEnabled by remember { mutableStateOf(android.animation.ValueAnimator.areAnimatorsEnabled()) }
    var prepared by remember { mutableStateOf(false) }
    var frameVisible by remember { mutableStateOf(false) }
    val running by rememberUpdatedState(foreground && animationsEnabled)
    DisposableEffect(lifecycle) {
        val observer=androidx.lifecycle.LifecycleEventObserver { _,event ->
            if(event==androidx.lifecycle.Lifecycle.Event.ON_START) { foreground=true;animationsEnabled=android.animation.ValueAnimator.areAnimatorsEnabled() }
            if(event==androidx.lifecycle.Lifecycle.Event.ON_STOP)foreground=false
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(running,prepared) { if(prepared)player?.let { if(running)it.start() else it.pause() } }
    val poster by produceState<android.graphics.Bitmap?>(null,resource) {
        value=withContext(Dispatchers.IO) { runCatching {
            val name=if(resource=="cat-wizard")"cat-wizard-poster" else resource
            context.assets.open("$name.jpg").use { android.graphics.BitmapFactory.decodeStream(it) }
        }.getOrNull() }
    }
    DisposableEffect(Unit) { onDispose { player?.release();player=null;outputSurface?.release();outputSurface=null } }
    Box(modifier.aspectRatio(4f/3f).clip(RoundedCornerShape(14.dp)).background(Color.Black).testTag("processing.animation").semantics { stateDescription=resource }) {
    AndroidView(modifier=Modifier.fillMaxSize(),factory={
        TextureView(context).apply { surfaceTextureListener=object:TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture:SurfaceTexture,w:Int,h:Int) {
                val surface=Surface(texture);outputSurface=surface
                val media=MediaPlayer();player=media
                fun next() {
                    val clip=deck.next() ?: return
                    prepared=false;frameVisible=false;media.reset()
                    context.assets.openFd("$clip.mp4").use { media.setDataSource(it.fileDescriptor,it.startOffset,it.length) }
                    media.setSurface(surface);media.setVolume(0f,0f);media.isLooping=false
                    resource=clip
                    media.setOnPreparedListener { if(player===it) { prepared=true;if(running)it.start() } }
                    media.prepareAsync()
                }
                media.setOnInfoListener { _,what,_ -> if(what==MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START)frameVisible=true;false }
                media.setOnCompletionListener { if(player===it)next() }
                media.setOnErrorListener { _,_,_ -> true }
                next()

            }
            override fun onSurfaceTextureDestroyed(texture:SurfaceTexture):Boolean { prepared=false;frameVisible=false;player?.release();player=null;outputSurface?.release();outputSurface=null;return true }
            override fun onSurfaceTextureSizeChanged(texture:SurfaceTexture,w:Int,h:Int) {}
            override fun onSurfaceTextureUpdated(texture:SurfaceTexture) {}
        } }
    })
    if(!frameVisible || !animationsEnabled)poster?.let { Image(it.asImageBitmap(),null,Modifier.fillMaxSize()) }
    }
}
