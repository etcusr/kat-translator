package org.openoffline.translator.android.camera

import android.Manifest
import android.content.pm.PackageManager
import android.widget.FrameLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.runner.RunWith
import org.openoffline.translator.android.MainActivity
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Root grants CAMERA and owns device exclusivity. Never saves, logs, or exports camera pixels. */
@RunWith(AndroidJUnit4::class)
class LiveCameraDeviceTest {
    @get:Rule val environment=org.openoffline.translator.android.UiTestEnvironment.wrap()
    @Test fun realPreviewCaptureStopAndReopenReleaseAllResources(){
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        assertEquals("Grant CAMERA before this hardware test",PackageManager.PERMISSION_GRANTED,instrumentation.targetContext.checkSelfPermission(Manifest.permission.CAMERA))
        val state=AtomicReference(CameraStatus())
        val frames=AtomicInteger()
        val invalid=AtomicReference<String?>(null)
        val firstFrame=CountDownLatch(1)
        var camera:LiveCamera?=null
        val scenario=ActivityScenario.launch(MainActivity::class.java)
        try{
            scenario.onActivity{activity->
                val controller=LiveCamera(activity,{state.set(it)},{frame->
                    try{
                        if(frame.bitmap.width<1||frame.bitmap.height<1||maxOf(frame.bitmap.width,frame.bitmap.height)>1600)invalid.set("Unbounded OCR frame")
                        frames.incrementAndGet();firstFrame.countDown()
                    }finally{frame.close()}
                })
                camera=controller
                activity.setContentView(FrameLayout(activity).apply{addView(controller.preview,FrameLayout.LayoutParams(-1,-1))})
                // An activation cancelled before Camera2 opens must not revive later.
                controller.start();controller.stop();controller.start()
            }
            assertTrue("No real camera frame; ${state.get()}",firstFrame.await(20,TimeUnit.SECONDS))
            await("Camera active"){state.get().active || state.get().error!=null}
            assertNull(state.get().error);assertTrue(state.get().active);assertNull(invalid.get())
            scenario.onActivity{camera!!.setFrameDelivery(false);camera!!.setZoom(minOf(2f,state.get().maxZoom));camera!!.focus(.5f,.5f)}
            instrumentation.waitForIdleSync()
            val count=frames.get();Thread.sleep(800)
            assertEquals("Paused frame delivery must not queue stale OCR work",count,frames.get())
            val captured=CountDownLatch(1);val captureError=AtomicReference<Throwable?>(null)
            scenario.onActivity{camera!!.capture{result->
                result.fold(onSuccess={bitmap->try{if(bitmap.width<1||bitmap.height<1||maxOf(bitmap.width,bitmap.height)>3072)captureError.set(AssertionError("Invalid real photo size"))}finally{bitmap.recycle()}},onFailure={captureError.set(it)})
                captured.countDown()
            }}
            assertTrue("Photo callback did not finish",captured.await(15,TimeUnit.SECONDS));assertNull(captureError.get())
            scenario.onActivity{camera!!.stop()}
            await("Camera stopped"){!state.get().active}
            scenario.onActivity{camera!!.setFrameDelivery(true);camera!!.start()}
            await("Camera reopened"){state.get().active && frames.get()>count}
            assertNull(state.get().error);assertNull(invalid.get())
            scenario.onActivity{camera!!.close();camera!!.close();camera=null}
        }finally{
            scenario.onActivity{camera?.close()};scenario.close()
        }
    }
    private fun await(message:String,predicate:()->Boolean){
        val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(15)
        while(!predicate() && System.nanoTime()<deadline)Thread.sleep(50)
        assertTrue(message,predicate())
    }
}
