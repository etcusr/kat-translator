package org.openoffline.translator.android

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Read-only system ASR probe. No microphone, remote recognizer or model download. */
@RunWith(AndroidJUnit4::class)
class PlatformSpeechProbeTest {
    @Test fun reportInstalledOfflineLanguageSupport() {
        val inst=InstrumentationRegistry.getInstrumentation()
        val context=inst.targetContext
        val available=SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        fun report(value:JSONObject)=inst.sendStatus(0,Bundle().apply { putString("stream","\nPLATFORM_ASR $value\n") })
        report(JSONObject().put("onDeviceAvailable",available))
        if(!available)return
        var recognizer:SpeechRecognizer?=null
        inst.runOnMainSync { recognizer=SpeechRecognizer.createOnDeviceSpeechRecognizer(context) }
        try {
            for(language in listOf("ru-RU","en-US")) {
                val done=CountDownLatch(1)
                val intent=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE,language)
                inst.runOnMainSync {
                    recognizer!!.checkRecognitionSupport(intent,context.mainExecutor,object:RecognitionSupportCallback {
                        override fun onSupportResult(support:RecognitionSupport) {
                            report(JSONObject().put("requested",language)
                                .put("installed",JSONArray(support.installedOnDeviceLanguages))
                                .put("downloadable",JSONArray(support.supportedOnDeviceLanguages))
                                .put("pending",JSONArray(support.pendingOnDeviceLanguages))
                                .put("online",JSONArray(support.onlineLanguages)))
                            done.countDown()
                        }
                        override fun onError(error:Int) { report(JSONObject().put("requested",language).put("error",error));done.countDown() }
                    })
                }
                assertTrue("System ASR support callback timed out",done.await(15,TimeUnit.SECONDS))
            }
        } finally { inst.runOnMainSync { recognizer?.destroy() } }
    }
}
