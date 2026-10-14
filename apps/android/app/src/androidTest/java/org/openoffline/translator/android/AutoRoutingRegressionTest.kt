package org.openoffline.translator.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.android.packages.PackageCatalog
import org.openoffline.translator.android.packages.PackageLanguageSetup

/** Real installed models, through product controls; UiTestEnvironment restores preferences. */
@RunWith(AndroidJUnit4::class)
class AutoRoutingRegressionTest {
    private val ui = createAndroidComposeRule<MainActivity>()
    @get:Rule val environment = UiTestEnvironment.wrap(ui)

    @Test fun autoSwitchesNativeOwnershipPassesSameLanguageAndUsesManualDirections() {
        lateinit var state: TranslatorState
        ui.runOnIdle {
            state = ViewModelProvider(ui.activity)[TranslatorState::class.java]
            state.mode = "text"
            state.setHistory(false); state.changeRecordAudio(false)
            state.changeAutomaticSpeech(false); state.changeMemorySaving(false)
            state.selectTranslation(AUTO_TRANSLATION)
        }
        ui.waitUntil(120_000) { state.packages.restored.value && state.deviceClass != null }
        ui.runOnIdle {
            assertFalse("This acceptance fixture requires compact-device Auto", state.strongDevice)
            assertNotNull(state.packages.installedPath(PackageCatalog.INDEX2B_ID))
            val plan = state.setupPlan(PackageLanguageSetup("ru", listOf("de"), false, false))
            assertTrue(plan.isValid)
            assertEquals(setOf("opus-tc-big-zle-de-int8", "opus-tc-big-de-zle-int8"), plan.ids.toSet())
        }
        fun run(text: String, source: String, target: String, expected: String, index: Boolean) {
            ui.runOnIdle { state.chooseLanguage(source, true); state.chooseLanguage(target, false) }
            ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement(text)
            ui.onNodeWithTag("text.translate").performClick()
            ui.waitUntil(180_000) { !state.busy && state.output.isNotBlank() || state.error != null }
            ui.runOnIdle {
                assertNull(state.error, state.error)
                assertTrue(state.output, state.output.contains(expected, ignoreCase = true))
                // Inspect actual owners after completion, not just the UI readiness flags.
                val field = TranslatorState::class.java.getDeclaredField("translationResources").apply { isAccessible = true }
                val resources = field.get(state) as TranslationResources<*, *>
                if (index) {
                    assertNotNull(resources.index); assertNotNull(resources.indexLease)
                    assertNull(resources.opus); assertNull(resources.opusLease)
                } else {
                    assertNotNull(resources.opus); assertNotNull(resources.opusLease)
                    assertNull(resources.index); assertNull(resources.indexLease)
                }
            }
        }
        run("Поезд отправляется завтра в 10:30.", "ru", "en", "train", false)
        run("Der Zug fährt morgen um 10:30 ab.", "de", "en", "train", true)
        run("Поезд отправляется завтра в 10:30.", "ru", "en", "train", false)
        ui.runOnIdle { state.chooseLanguage("auto", true); state.chooseLanguage("en", false) }
        val unchanged = "The train leaves tomorrow at 10:30."
        ui.onNodeWithTag("text.source.input").performScrollTo().performTextReplacement(unchanged)
        ui.onNodeWithTag("text.translate").performClick()
        ui.waitUntil(30_000) { !state.busy && state.output.isNotBlank() || state.error != null }
        ui.runOnIdle { assertNull(state.error); assertEquals("en", state.detectedSource); assertEquals(unchanged, state.output) }
        run("Поезд отправляется завтра в 10:30.", "ru", "de", "Zug", false)
        ui.runOnIdle { state.unload() }
        ui.waitUntil(30_000) { !state.ready && !state.opusReady }
    }
}
