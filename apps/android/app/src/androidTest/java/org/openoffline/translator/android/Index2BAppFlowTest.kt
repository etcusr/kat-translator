package org.openoffline.translator.android

import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog

/** Index 2B through the real text controls: RU→EN, EN→RU, cancel, unload and reload.
 * Optional -e articleFile <path under /data/local/tmp> supplies a local article; the
 * default text is synthetic so the test carries no private material. */
@RunWith(AndroidJUnit4::class)
class Index2BAppFlowTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)

    private fun article():String {
        val inst=InstrumentationRegistry.getInstrumentation()
        val path=InstrumentationRegistry.getArguments().getString("articleFile")
            ?: return "Городской совет утвердил план ремонта трёх мостов. Работы начнутся 14 марта и продлятся 120 дней. " +
                "На время ремонта автобусы 7 и 12 изменят маршрут, а стоимость проезда останется прежней.\n\n" +
                "Мэр сообщил, что бюджет проекта составит 85 миллионов рублей. Жители смогут задать вопросы на встрече в пятницу в 18:00."
        require(path.startsWith("/data/local/tmp/") && !path.contains(".."))
        val pipes=inst.uiAutomation.executeShellCommandRw("sh")
        ParcelFileDescriptor.AutoCloseOutputStream(pipes[1]).use { it.write("exec cat '$path'\n".toByteArray()) }
        return ParcelFileDescriptor.AutoCloseInputStream(pipes[0]).use { it.readBytes().toString(Charsets.UTF_8) }.trim()
    }

    private fun report(row:JSONObject) = InstrumentationRegistry.getInstrumentation()
        .sendStatus(0,Bundle().apply { putString("stream","\nKAT_INDEX2B ${row}\n") })

    @Test fun translateCancelReloadThroughTextControls() {
        lateinit var state:TranslatorState
        val source=article()
        ui.runOnIdle {
            state=ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode="text";state.setHistory(false);state.changeRecordAudio(false);state.changeMemorySaving(false)
            state.changeAutomaticSpeech(false);state.selectTranslation(PackageCatalog.MULTILINGUAL_BACKEND)
        }
        ui.waitUntil(120_000) { state.packages.restored.value }
        ui.runOnIdle {
            assertNotNull("Index 2B package must be installed",state.packages.installedPath(PackageCatalog.INDEX2B_ID))
            assertFalse("MTP stays a 9B-only policy",state.mtpActive)
            state.chooseLanguage("ru",true);state.chooseLanguage("en",false)
        }
        val rows=JSONArray()
        fun run(label:String,text:String,from:String,to:String,numbers:Boolean):String {
            ui.runOnIdle { state.chooseLanguage(from,true);state.chooseLanguage(to,false) }
            ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement(text)
            val start=System.nanoTime()
            ui.onNodeWithTag("text.translate").performClick()
            ui.waitUntil(300_000) { !state.busy && state.output.isNotBlank() || state.error!=null }
            val wall=(System.nanoTime()-start)/1e9
            var output=""
            ui.runOnIdle {
                assertNull(state.error,state.error)
                output=state.output
                val timing=state.timing
                val row=JSONObject().put("case",label).put("wallSeconds",wall).put("translationSeconds",timing?.translation)
                    .put("modelLoadSeconds",timing?.modelLoad).put("firstTokenSeconds",state.firstToken).put("segments",state.segmentCount)
                    .put("inputChars",text.length).put("outputChars",output.length).put("runtime",state.translationRuntimeLabel).put("output",output)
                rows.put(row);report(row)
            }
            assertTrue(output.isNotBlank())
            if(numbers)Regex("\\d+").findAll(text).forEach { assertTrue("Missing number ${it.value}",output.contains(it.value)) }
            return output
        }
        val english=run("ru-en-first",source,"ru","en",true)
        run("ru-en-warm",source,"ru","en",true)
        run("en-ru",english,"en","ru",true)

        // Cancel a running request, then translate again with the same engine.
        ui.runOnIdle { state.chooseLanguage("ru",true);state.chooseLanguage("en",false) }
        ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement(source)
        ui.onNodeWithTag("text.translate").performClick()
        ui.waitUntil(120_000) { state.ready && state.busy && state.segmentCount>0 || !state.busy }
        ui.runOnIdle { assertTrue("Request must still be active before cancel",state.busy) }
        ui.onNodeWithTag("processing.cancel").performScrollTo().performClick()
        ui.waitUntil(45_000) { !state.busy }
        ui.onNodeWithTag("processing.overlay").assertDoesNotExist()
        report(JSONObject().put("case","cancel").put("ok",true))
        run("after-cancel",source,"ru","en",true)

        // Unload from memory, then a cold reload through the same controls.
        ui.runOnIdle { state.unload() }
        ui.waitUntil(30_000) { !state.modelReady }
        run("after-reload",source,"ru","en",true)
        ui.runOnIdle { assertTrue(state.modelReady) }
        InstrumentationRegistry.getInstrumentation().targetContext.filesDir.resolve("index2b-app-flow.json").writeText(rows.toString(2))
    }
}
