package org.openoffline.translator.android

import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Exercises the controls that previously differed from iOS; preserves user settings. */
@RunWith(AndroidJUnit4::class)
class SettingsParityTest {
    val ui=createAndroidComposeRule<MainActivity>()
    @get:Rule val environment=UiTestEnvironment.wrap(ui)
    private fun state()=ViewModelProvider(ui.activity)[TranslatorState::class.java]
    private fun screenshot(name:String) {
        ui.waitForIdle()
        val inst=InstrumentationRegistry.getInstrumentation()
        val bitmap=checkNotNull(inst.uiAutomation.takeScreenshot())
        try { File(inst.targetContext.getExternalFilesDir(null),name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) } }
        finally { bitmap.recycle() }
    }
    @Test fun settingsUseExplicitPickersStepperAndConditionalVerification() {
        var language="";var mode="";var minutes=0;var silence=0;var preprocessing=false;var verification=false
        val orientation=ui.activity.requestedOrientation
        ui.runOnIdle {
            language=state().interfaceLanguage;mode=state().recordingMode;minutes=state().recordingMinutes
            silence=state().silenceSeconds
            preprocessing=state().recordingPreprocessing;verification=state().recordingVerification
            state().changeInterfaceLanguage("ru")
            ui.activity.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        try {
            ui.waitUntil(5_000) { ui.activity.resources.configuration.orientation==android.content.res.Configuration.ORIENTATION_PORTRAIT }
            ui.onNodeWithTag("toolbar.settings").performClick()
            ui.onNodeWithTag("sheet.header").assertIsDisplayed()
            screenshot("ui-settings-top.png")
            ui.onNodeWithTag("settings.interfaceLanguage").performClick()
            listOf("system","ru","en").forEach { ui.onNodeWithTag("settings.interfaceLanguage.$it").assertIsDisplayed() }
            ui.runOnIdle { assertEquals("Opening a picker must not cycle its value","ru",state().interfaceLanguage) }
            ui.onNodeWithTag("settings.interfaceLanguage.en").performClick()
            ui.runOnIdle { assertEquals("en",state().interfaceLanguage) }
            ui.onNodeWithTag("settings.interfaceLanguage").performClick()
            ui.onNodeWithTag("settings.interfaceLanguage.ru").performClick()
            ui.onNodeWithTag("settings.recordingMode").performClick()
            listOf("hold","toggle").forEach { ui.onNodeWithTag("settings.recordingMode.$it").assertIsDisplayed() }
            ui.runOnIdle { assertEquals(mode,state().recordingMode) }
            val next=if(mode=="hold")"toggle" else "hold"
            ui.onNodeWithTag("settings.recordingMode.$next").performClick()
            ui.runOnIdle { assertEquals(next,state().recordingMode) }
            val delta=if(minutes==30)-1 else 1
            ui.onNodeWithTag("recording.limit.stepper.${if(delta==1)"plus" else "minus"}").performScrollTo().performClick()
            ui.runOnIdle { assertEquals(minutes+delta,state().recordingMinutes) }
            val nextSilence=if(silence==7)8 else 7
            ui.onNodeWithTag("settings.recordingSilence").performScrollTo().performSemanticsAction(SemanticsActions.SetProgress) { assertTrue(it(nextSilence.toFloat())) }
            ui.runOnIdle { assertEquals(nextSilence,state().silenceSeconds) }
            if(!preprocessing)ui.onNodeWithTag("settings.recordingPreprocessing").performScrollTo().performClick()
            ui.onNodeWithTag("settings.recordingPreviewVerification").performScrollTo().assertIsDisplayed().performClick()
            ui.runOnIdle { assertEquals(!verification,state().recordingVerification) }
            ui.onNodeWithTag("settings.recordingPreprocessing").performScrollTo().performClick()
            ui.onNodeWithTag("settings.recordingPreviewVerification").assertDoesNotExist()
            ui.onNodeWithTag("settings.recordText").performScrollTo().assertIsDisplayed()
            var originalCount=0
            ui.runOnIdle { originalCount=state().historyCount }
            val draftCount=if(originalCount==0 || originalCount==10000)0 else originalCount+1
            ui.onNodeWithTag("settings.textCount").performScrollTo().performTextReplacement(draftCount.toString())
            ui.onNodeWithText("Голоса и образцы").performScrollTo().performClick()
            ui.onNodeWithTag("voices.list").assertIsDisplayed()
            ui.onNodeWithTag("sheet.back").performClick()
            ui.onNodeWithTag("settings.textCount").performScrollTo().assertTextEquals(draftCount.toString())
            ui.runOnIdle { assertEquals("Settings must save without an Apply button",draftCount,state().historyCount);assertEquals(draftCount,ui.activity.getSharedPreferences("kat",0).getInt("historyCount",-1)) }
            // Restore before closing, when retention cleanup runs.
            ui.onNodeWithTag("settings.textCount").performTextReplacement(originalCount.toString())
            ui.onNodeWithTag("history.recordAudio").performScrollTo().assertIsDisplayed()
            ui.onNodeWithTag("history.recordImages").performScrollTo().assertIsDisplayed()
            ui.onNodeWithTag("settings.saveRetention").assertDoesNotExist()
            screenshot("ui-settings-history.png")
            ui.onNodeWithTag("settings.copyVersion").performScrollTo().assertIsDisplayed()
            screenshot("ui-settings-about.png")
            ui.onNodeWithTag("sheet.close").performClick()
        } finally {
            ui.runOnIdle {
                state().changeInterfaceLanguage(language);state().changeRecordingMode(mode);state().setRecordingLimit(minutes)
                state().setSilence(silence)
                state().changeRecordingPreprocessing(preprocessing);state().changeRecordingVerification(verification)
                ui.activity.requestedOrientation=orientation
            }
        }
    }
}
