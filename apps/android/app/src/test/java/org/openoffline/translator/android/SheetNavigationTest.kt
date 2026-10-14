package org.openoffline.translator.android

import org.junit.Assert.assertEquals
import org.junit.Test

class SheetNavigationTest {
    @Test fun nestedRecognitionModelsDoneKeepsSettings() {
        assertEquals(SheetNavigation.Destination("settings",emptyList()),SheetNavigation.close("models",listOf("settings"),false))
    }
    @Test fun modelLanguagesDoneClosesDetailsOnly() {
        assertEquals(SheetNavigation.Destination("models",listOf("settings")),SheetNavigation.close("modelLanguages:index",listOf("settings","models","modelInfo:index"),false))
        assertEquals(SheetNavigation.Destination("modelInfo:index",listOf("settings","models")),SheetNavigation.close("modelLanguages:index",listOf("settings","models","modelInfo:index"),true))
    }
    @Test fun setupAndImageReaderReturnToTheirOwners() {
        assertEquals(SheetNavigation.Destination("models",emptyList()),SheetNavigation.close("setup",listOf("models"),false))
        assertEquals(SheetNavigation.Destination("models",emptyList()),SheetNavigation.close("opusDirections",listOf("models"),false))
        assertEquals(SheetNavigation.Destination("models",emptyList()),SheetNavigation.close("opusDirections",listOf("models"),true))
        assertEquals(SheetNavigation.Destination("history",emptyList()),SheetNavigation.close("historyImage",listOf("history"),false))
    }
    @Test fun settingsDestinationsHaveStepwiseBackAndRootDone() {
        for(route in listOf("voices","licenses","privacy")) {
            assertEquals(SheetNavigation.Destination("settings",emptyList()),SheetNavigation.close(route,listOf("settings"),true))
            assertEquals(SheetNavigation.Destination("",emptyList()),SheetNavigation.close(route,listOf("settings"),false))
        }
    }
    @Test fun languageVoiceBackKeepsPickerAndDoneDismissesIt() {
        assertEquals(SheetNavigation.Destination("target",emptyList()),SheetNavigation.close("voices:ja",listOf("target"),true))
        assertEquals(SheetNavigation.Destination("",emptyList()),SheetNavigation.close("voices:ja",listOf("target"),false))
    }
    @Test fun rootCameraAndReadersDoNotInventParents() {
        for(route in listOf("models","settings","history","source","target","ocrModels","cameraText","original","translation","diagnostics")) {
            for(back in listOf(true,false))assertEquals(SheetNavigation.Destination("",emptyList()),SheetNavigation.close(route,emptyList(),back))
        }
    }
}
