package org.openoffline.translator.android.camera

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.hardware.camera2.params.MeteringRectangle
import android.hardware.display.DisplayManager
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import android.view.TextureView
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.max

/** Main-thread state. Errors are stable short codes for the UI's localized message mapping. */
data class CameraStatus(val active:Boolean=false,val capturing:Boolean=false,val error:String?=null,val maxZoom:Float=1f,val revision:Long=0)

/** One bounded upright OCR frame. Close in a worker finally block after reading its bitmap. */
class CameraFrame internal constructor(val bitmap:Bitmap,val revision:Long,private val release:()->Unit):AutoCloseable {
    private val closed=AtomicBoolean(false)
    override fun close(){if(closed.compareAndSet(false,true)){bitmap.recycle();release()}}
}

/** Rear Camera2 preview + YUV OCR frames + real JPEG shutter. No inference runs here.
 * Construct and invoke methods on main. Call stop on lifecycle ON_STOP, close on disposal.
 * Callbacks run on main. The caller owns each captured Bitmap and must close every CameraFrame.
 */
class LiveCamera(context:Context,private val onState:(CameraStatus)->Unit,private val onFrame:(CameraFrame)->Unit):AutoCloseable {
    val preview=TextureView(context)
    private val app=context.applicationContext
    private val main=Handler(Looper.getMainLooper())
    private val thread=HandlerThread("kat-camera").apply{start()}
    private val handler=Handler(thread.looper)
    private val manager=app.getSystemService(CameraManager::class.java)
    private val displays=app.getSystemService(DisplayManager::class.java)
    private val generation=AtomicLong(0)
    private val frameRevision=AtomicLong(0)
    val revision:Long get()=frameRevision.get()
    @Volatile private var wanted=false
    @Volatile private var closed=false
    @Volatile private var deliverFrames=true
    @Volatile private var displayDegrees=0
    @Volatile private var sensorOrientation=90
    @Volatile private var previewSize=Size(1280,720)
    @Volatile private var viewWidth=1
    @Volatile private var viewHeight=1
    private val delivering=AtomicBoolean(false)
    // These resources are owned only by handler, including all Camera2 callbacks.
    private var device:CameraDevice?=null
    private var session:CameraCaptureSession?=null
    private var yuv:ImageReader?=null
    private var jpeg:ImageReader?=null
    private var surface:Surface?=null
    private var characteristics:CameraCharacteristics?=null
    private var request:CaptureRequest.Builder?=null
    private var opening=false
    private var zoom=1f
    private var maximumZoom=1f
    private var crop:Rect?=null
    private var lastFrame=0L
    private var pendingPhoto:((Result<Bitmap>)->Unit)?=null
    private var photoGeneration=0L
    private var photoTimeout:Runnable?=null
    private var status=CameraStatus()
    private val displayListener=object:DisplayManager.DisplayListener {
        override fun onDisplayAdded(id:Int){}
        override fun onDisplayRemoved(id:Int){}
        override fun onDisplayChanged(id:Int){if(preview.display?.displayId==id)updateTransform()}
    }
    init {
        preview.surfaceTextureListener=object:TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture:SurfaceTexture,width:Int,height:Int){updateTransform();if(wanted)open(texture)}
            override fun onSurfaceTextureSizeChanged(texture:SurfaceTexture,width:Int,height:Int){updateTransform()}
            override fun onSurfaceTextureDestroyed(texture:SurfaceTexture):Boolean {
                generation.incrementAndGet();frameRevision.incrementAndGet()
                if(!closed)handler.post{releaseCamera();emit(CameraStatus(revision=revision))}
                return true
            }
            override fun onSurfaceTextureUpdated(texture:SurfaceTexture){}
        }
        displays.registerDisplayListener(displayListener,main)
    }
    private fun mainThread(){check(Looper.myLooper()==Looper.getMainLooper()){"Camera methods require main thread"}}
    fun start(){
        mainThread();check(!closed){"Camera closed"}
        if(app.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){emit(CameraStatus(error="camera.permission"));return}
        if(wanted)return
        wanted=true;generation.incrementAndGet();frameRevision.incrementAndGet();updateTransform()
        preview.surfaceTexture?.let(::open)
    }
    fun stop(){
        mainThread();wanted=false;generation.incrementAndGet();frameRevision.incrementAndGet()
        if(!closed)handler.post{releaseCamera();emit(CameraStatus(revision=revision))}
    }
    override fun close(){
        mainThread();if(closed)return
        wanted=false;generation.incrementAndGet();frameRevision.incrementAndGet();closed=true
        displays.unregisterDisplayListener(displayListener);preview.surfaceTextureListener=null
        handler.post{releaseCamera();thread.quitSafely()}
    }
    fun setFrameDelivery(enabled:Boolean){mainThread();deliverFrames=enabled}
    fun setZoom(factor:Float){
        mainThread();require(factor.isFinite() && factor>=1f)
        handler.post{zoom=factor.coerceIn(1f,maximumZoom);applyZoom();repeat()}
    }
    fun focus(xFraction:Float,yFraction:Float){
        mainThread();if(!xFraction.isFinite()||!yFraction.isFinite())return
        val point=CameraGeometry.focus(xFraction,yFraction,viewWidth,viewHeight,previewSize.width,previewSize.height,CameraGeometry.rotation(sensorOrientation,displayDegrees))
        handler.post{
            val bounds=crop ?: return@post;val builder=request ?: return@post
            val size=max(20,minOf(bounds.width(),bounds.height())/10)
            val x=(bounds.left+point.first*bounds.width()-size/2).toInt().coerceIn(bounds.left,max(bounds.left,bounds.right-size))
            val y=(bounds.top+point.second*bounds.height()-size/2).toInt().coerceIn(bounds.top,max(bounds.top,bounds.bottom-size))
            val region=arrayOf(MeteringRectangle(Rect(x,y,minOf(bounds.right,x+size),minOf(bounds.bottom,y+size)),MeteringRectangle.METERING_WEIGHT_MAX))
            try{
                if((characteristics?.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0)>0)builder.set(CaptureRequest.CONTROL_AF_REGIONS,region)
                if((characteristics?.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0)>0)builder.set(CaptureRequest.CONTROL_AE_REGIONS,region)
                if(characteristics?.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.contains(CaptureRequest.CONTROL_AF_MODE_AUTO)==true){
                    builder.set(CaptureRequest.CONTROL_AF_MODE,CaptureRequest.CONTROL_AF_MODE_AUTO)
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER,CaptureRequest.CONTROL_AF_TRIGGER_START)
                    session?.capture(builder.build(),null,handler)
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER,CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
                    repeat()
                    val current=generation.get()
                    handler.postDelayed({if(current==generation.get()){setContinuousFocus(builder);repeat()}},3000)
                }else repeat()
            }catch(_:Exception){if(wanted && !closed)fail("camera.focus")}
        }
    }
    fun capture(callback:(Result<Bitmap>)->Unit){
        mainThread();val current=generation.get()
        handler.post{
            val camera=device;val reader=jpeg;val active=session
            if(!wanted||current!=generation.get()||camera==null||reader==null||active==null||pendingPhoto!=null){main.post{callback(Result.failure(IllegalStateException("camera.unavailable")))};return@post}
            pendingPhoto=callback;photoGeneration=current;emit(status.copy(capturing=true,error=null))
            try{
                val still=camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply{
                    addTarget(reader.surface);set(CaptureRequest.CONTROL_MODE,CaptureRequest.CONTROL_MODE_AUTO)
                    set(CaptureRequest.JPEG_ORIENTATION,CameraGeometry.rotation(sensorOrientation,displayDegrees))
                    set(CaptureRequest.JPEG_QUALITY,95.toByte());crop?.let{set(CaptureRequest.SCALER_CROP_REGION,it)}
                    set(CaptureRequest.CONTROL_AF_MODE,request?.get(CaptureRequest.CONTROL_AF_MODE) ?: CaptureRequest.CONTROL_AF_MODE_OFF)
                }
                val timeout=Runnable{finishPhoto(Result.failure(IllegalStateException("camera.capture.timeout")))}
                photoTimeout=timeout;handler.postDelayed(timeout,10000)
                active.capture(still.build(),object:CameraCaptureSession.CaptureCallback(){
                    override fun onCaptureFailed(session:CameraCaptureSession,request:CaptureRequest,failure:CaptureFailure){finishPhoto(Result.failure(IllegalStateException("camera.capture")))}
                },handler)
            }catch(error:Exception){finishPhoto(Result.failure(error))}
        }
    }
    private fun finishPhoto(result:Result<Bitmap>){
        photoTimeout?.let(handler::removeCallbacks);photoTimeout=null
        val callback=pendingPhoto;pendingPhoto=null
        val photoRevision=photoGeneration
        emit(status.copy(capturing=false))
        if(callback!=null)main.post{
            if(closed||!wanted||photoRevision!=generation.get()){
                result.getOrNull()?.recycle();callback(Result.failure(CancellationException("Camera stopped")))
            }else callback(result)
        } else result.getOrNull()?.recycle()
    }
    private fun emit(next:CameraStatus){
        status=next
        val current=generation.get()
        main.post{if(!closed && current==generation.get())onState(next.copy(revision=revision))}
    }
    @SuppressLint("MissingPermission")
    private fun open(texture:SurfaceTexture){
        val current=generation.get()
        handler.post{
            if(!wanted||closed||current!=generation.get()||opening||device!=null)return@post
            opening=true
            try{
                val id=manager.cameraIdList.firstOrNull{manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING)==CameraCharacteristics.LENS_FACING_BACK}
                    ?: error("camera.unavailable")
                val info=manager.getCameraCharacteristics(id);characteristics=info
                sensorOrientation=info.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
                maximumZoom=minOf(8f,info.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f)
                val sizes=info.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: error("camera.unavailable")
                val ys=sizes.getOutputSizes(ImageFormat.YUV_420_888) ?: error("camera.unavailable")
                val ps=sizes.getOutputSizes(SurfaceTexture::class.java) ?: error("camera.unavailable")
                val common=ys.filter{it in ps && max(it.width,it.height)<=1600}
                val size=common.maxByOrNull{it.width.toLong()*it.height} ?: ys.filter{max(it.width,it.height)<=1600}.maxByOrNull{it.width.toLong()*it.height} ?: error("camera.resolution")
                previewSize=ps.filter{max(it.width,it.height)<=1920}.minByOrNull{abs(it.width.toFloat()/it.height-size.width.toFloat()/size.height)*10000+abs(it.width-size.width)} ?: error("camera.resolution")
                val photos=sizes.getOutputSizes(ImageFormat.JPEG) ?: error("camera.unavailable")
                val photo=photos.filter{it.width.toLong()*it.height<=13_000_000}.maxByOrNull{it.width.toLong()*it.height} ?: photos.minBy{it.width.toLong()*it.height}
                texture.setDefaultBufferSize(previewSize.width,previewSize.height);surface=Surface(texture)
                yuv=ImageReader.newInstance(size.width,size.height,ImageFormat.YUV_420_888,2).also{it.setOnImageAvailableListener({reader->readFrame(reader,current)},handler)}
                jpeg=ImageReader.newInstance(photo.width,photo.height,ImageFormat.JPEG,2).also{it.setOnImageAvailableListener({reader->readPhoto(reader,current)},handler)}
                main.post{if(current==generation.get())updateTransform()}
                manager.openCamera(id,object:CameraDevice.StateCallback(){
                    override fun onOpened(camera:CameraDevice){
                        if(!wanted||closed||current!=generation.get()){camera.close();return}
                        opening=false
                        device=camera;configure(camera,current)
                    }
                    override fun onDisconnected(camera:CameraDevice){camera.close();if(current==generation.get())fail("camera.disconnected")}
                    override fun onError(camera:CameraDevice,error:Int){camera.close();if(current==generation.get())fail("camera.unavailable")}
                },handler)
            }catch(error:Exception){if(current==generation.get())fail(if(error is SecurityException)"camera.permission" else "camera.unavailable")}
        }
    }
    @Suppress("DEPRECATION")
    private fun configure(camera:CameraDevice,current:Long){
        val targets=listOfNotNull(surface,yuv?.surface,jpeg?.surface)
        if(targets.size!=3){fail("camera.unavailable");return}
        try{camera.createCaptureSession(targets,object:CameraCaptureSession.StateCallback(){
            override fun onConfigured(configured:CameraCaptureSession){
                if(!wanted||closed||current!=generation.get()||device!==camera){configured.close();return}
                session=configured
                try{
                    val builder=camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    // Bind the exact surfaces configured for this session, not mutable fields.
                    builder.addTarget(targets[0]);builder.addTarget(targets[1])
                    builder.set(CaptureRequest.CONTROL_MODE,CaptureRequest.CONTROL_MODE_AUTO)
                    setContinuousFocus(builder);request=builder;applyZoom()
                    if(repeat() && current==generation.get())emit(CameraStatus(active=true,maxZoom=maximumZoom,revision=revision))
                }catch(_:Exception){if(current==generation.get() && wanted && !closed)fail("camera.unavailable")}
            }
            override fun onConfigureFailed(configured:CameraCaptureSession){configured.close();if(current==generation.get())fail("camera.configuration")}
        },handler)}catch(_:Exception){fail("camera.configuration")}
    }
    private fun setContinuousFocus(builder:CaptureRequest.Builder){
        val modes=characteristics?.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
        builder.set(CaptureRequest.CONTROL_AF_MODE,when{CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE in modes->CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE;CaptureRequest.CONTROL_AF_MODE_AUTO in modes->CaptureRequest.CONTROL_AF_MODE_AUTO;else->CaptureRequest.CONTROL_AF_MODE_OFF})
        builder.set(CaptureRequest.CONTROL_AF_TRIGGER,CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
    }
    private fun applyZoom(){
        val sensor=characteristics?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return
        val factor=zoom.coerceIn(1f,maximumZoom);val w=(sensor.width()/factor).toInt();val h=(sensor.height()/factor).toInt()
        crop=Rect(sensor.centerX()-w/2,sensor.centerY()-h/2,sensor.centerX()+w/2,sensor.centerY()+h/2)
        request?.set(CaptureRequest.SCALER_CROP_REGION,crop)
    }
    private fun repeat():Boolean {
        val current=generation.get()
        if(!wanted||closed)return false
        val builder=request ?: return false
        val active=session ?: return false
        return try { active.setRepeatingRequest(builder.build(),null,handler);true }
        catch(_:Exception) {
            // The main thread can destroy the TextureView between this check and
            // Camera2 submission. Abandoned/closed surfaces also throw runtime exceptions.
            if(current==generation.get() && wanted && !closed)fail("camera.unavailable")
            false
        }
    }
    private fun readFrame(reader:ImageReader,current:Long){
        val image=try{reader.acquireLatestImage()}catch(_:IllegalStateException){null} ?: return
        try{
            val now=SystemClock.elapsedRealtime()
            if(!wanted||closed||current!=generation.get()||!deliverFrames||pendingPhoto!=null||now-lastFrame<350||!delivering.compareAndSet(false,true))return
            lastFrame=now;val rev=revision
            val bitmap=try{CameraPixels.yuv(image,CameraGeometry.rotation(sensorOrientation,displayDegrees))}catch(_:Exception){delivering.set(false);return}
            val frame=CameraFrame(bitmap,rev){delivering.set(false)}
            main.post{
                if(!wanted||closed||current!=generation.get()||rev!=revision||!deliverFrames)frame.close()
                else try{onFrame(frame)}catch(error:Exception){frame.close();throw error}
            }
        }finally{image.close()}
    }
    private fun readPhoto(reader:ImageReader,current:Long){
        val image=try{reader.acquireLatestImage()}catch(_:IllegalStateException){null} ?: return
        try{
            if(current!=generation.get()||pendingPhoto==null)return
            val buffer=image.planes[0].buffer
            if(buffer.remaining()>40_000_000){finishPhoto(Result.failure(IllegalStateException("camera.image")));return}
            val bytes=ByteArray(buffer.remaining());buffer.get(bytes)
            finishPhoto(runCatching{CameraPixels.jpeg(bytes)})
        }finally{image.close()}
    }
    private fun fail(code:String){wanted=false;releaseCamera();emit(CameraStatus(error=code,maxZoom=maximumZoom,revision=revision))}
    private fun releaseCamera(){
        opening=false
        try{session?.stopRepeating()}catch(_:Exception){}
        session?.close();session=null;device?.close();device=null
        yuv?.close();yuv=null;jpeg?.close();jpeg=null;surface?.release();surface=null;request=null;characteristics=null;crop=null
        if(pendingPhoto!=null)finishPhoto(Result.failure(CancellationException("Camera stopped")))
    }
    private fun updateTransform(){
        mainThread();viewWidth=preview.width.coerceAtLeast(1);viewHeight=preview.height.coerceAtLeast(1)
        val degrees=when(preview.display?.rotation){Surface.ROTATION_90->90;Surface.ROTATION_180->180;Surface.ROTATION_270->270;else->0}
        if(degrees!=displayDegrees){displayDegrees=degrees;frameRevision.incrementAndGet()}
        val rotation=CameraGeometry.rotation(sensorOrientation,degrees)
        val bw=previewSize.width;val bh=previewSize.height
        val uprightW=if(rotation%180==0)bw else bh;val uprightH=if(rotation%180==0)bh else bw
        val scale=max(viewWidth.toFloat()/uprightW,viewHeight.toFloat()/uprightH)
        val dx=(viewWidth-uprightW*scale)/2;val dy=(viewHeight-uprightH*scale)/2
        val source=floatArrayOf(0f,0f,viewWidth.toFloat(),0f,viewWidth.toFloat(),viewHeight.toFloat(),0f,viewHeight.toFloat())
        val dest=FloatArray(8)
        val corners=arrayOf(0f to 0f,1f to 0f,1f to 1f,0f to 1f)
        for(i in corners.indices){val p=CameraGeometry.upright(corners[i].first,corners[i].second,rotation);dest[i*2]=dx+p.first*uprightW*scale;dest[i*2+1]=dy+p.second*uprightH*scale}
        preview.setTransform(Matrix().apply{setPolyToPoly(source,0,dest,0,4)})
    }
}
