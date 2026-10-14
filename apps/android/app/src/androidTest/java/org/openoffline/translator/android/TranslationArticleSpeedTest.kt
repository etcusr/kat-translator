package org.openoffline.translator.android

import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Same articles through the real text controls for any installed backend.
 * -e backend opus|index2b|index, -e partner en|de|fr|es, -e ruFile / -e partnerFile (under /data/local/tmp), -e passes N. */
@RunWith(AndroidJUnit4::class)
class TranslationArticleSpeedTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    private fun read(path:String):String {
        require(path.startsWith("/data/local/tmp/") && !path.contains(".."))
        val pipes=InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommandRw("sh")
        ParcelFileDescriptor.AutoCloseOutputStream(pipes[1]).use { it.write("exec cat '$path'\n".toByteArray()) }
        return ParcelFileDescriptor.AutoCloseInputStream(pipes[0]).use { it.readBytes().toString(Charsets.UTF_8) }.trim()
    }

    @Test fun articlesThroughTextControls() {
        val args=InstrumentationRegistry.getArguments()
        val backend=args.getString("backend","opus")!!
        val passes=args.getString("passes","2")!!.toInt()
        val partner=args.getString("partner","en")!!
        val cases=listOfNotNull(args.getString("ruFile")?.let { Triple("ru-$partner",read(it),"ru" to partner) },
            (args.getString("partnerFile") ?: args.getString("enFile"))?.let { Triple("$partner-ru",read(it),partner to "ru") })
        assertTrue("Pass -e ruFile and/or -e partnerFile",cases.isNotEmpty())
        lateinit var state:TranslatorState
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="text";state.setHistory(false);state.changeRecordAudio(false);state.changeMemorySaving(false)
            state.changeAutomaticSpeech(false);state.selectTranslation(backend)
        }
        ui.waitUntil(120_000) { state.packages.restored.value }
        ui.runOnIdle { assertTrue("$backend must be installed",state.installed) }
        repeat(passes) { pass ->
            for((label,text,pair) in cases) {
                ui.runOnIdle { state.chooseLanguage(pair.first,true);state.chooseLanguage(pair.second,false) }
                ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement(text)
                val start=System.nanoTime()
                ui.onNodeWithTag("text.translate").performClick()
                ui.waitUntil(600_000) { !state.busy && state.output.isNotBlank() || state.error!=null }
                val wall=(System.nanoTime()-start)/1e9
                ui.runOnIdle {
                    assertNull(state.error,state.error)
                    val timing=state.timing
                    val row=JSONObject().put("backend",backend).put("case",label).put("pass",pass+1).put("wallSeconds",wall)
                        .put("translationSeconds",timing?.translation).put("modelLoadSeconds",timing?.modelLoad)
                        .put("firstTokenSeconds",state.firstToken).put("segments",state.segmentCount)
                        .put("inputChars",text.length).put("runtime",state.translationRuntimeLabel).put("output",state.output)
                    InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply { putString("stream","\nKAT_SPEED $row\n") })
                }
            }
        }
    }
}
