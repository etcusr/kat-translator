package org.openoffline.translator.android.packages

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class RecognitionRoutingTest {
    @Test fun compactWhisperRetainsAllLanguagesAndAliasesWithoutReplacingAuto() {
        val all=catalog()
        val full=all.single { it.id=="whisper-large-v3-turbo-f16" }
        val compact=all.single { it.id=="whisper-large-v3-turbo-q8_0" }
        assertEquals("whisper",compact.backend)
        assertEquals(full.languages,compact.languages)
        for(language in full.languages)assertEquals(full.runtimeLanguage(language),compact.runtimeLanguage(language))
        assertTrue(compact.downloadBytes<full.downloadBytes)
        assertNull(compact.unavailableReason)
        assertEquals("gigaam-v3-int8",RecognitionRouting.recommended(all,"ru")!!.id)
    }
    private fun catalog():List<OfflinePackage> {
        var root=File(System.getProperty("user.dir")!!)
        while(!File(root,"assets/catalogs/models.json").exists())root=root.parentFile ?: error("No catalog")
        return PackageCatalog.load { File(root,"assets/catalogs/$it").readText() }
    }
    @Test fun russianHasPriorityEvenWhenParakeetAlsoSupportsIt() {
        val all=catalog()
        assertTrue(all.single { it.id=="parakeet-v3-int8" }.supports("ru"))
        assertEquals("gigaam-v3-int8",RecognitionRouting.recommended(all.reversed(),"ru")!!.id)
    }
    @Test fun englishAlwaysUsesV2RegardlessOfCatalogOrder() {
        val all=catalog()
        assertEquals(setOf("en"),all.single { it.id=="parakeet-v2-en-int8" }.languages)
        for(order in listOf(all,all.reversed()))assertEquals("parakeet-v2-en-int8",RecognitionRouting.recommended(order,"en")!!.id)
    }
    @Test fun everyOtherWhisperLanguageUsesQ8IncludingAuto() {
        val all=catalog()
        val whisper=all.single { it.id=="whisper-large-v3-turbo-q8_0" }
        for(language in (whisper.languages-setOf("ru","en"))+"auto") {
            assertEquals(language,whisper.id,RecognitionRouting.recommended(all.reversed(),language)!!.id)
        }
        assertNull(RecognitionRouting.recommended(all,"invalid"))
    }
    @Test fun missingOrUnavailableRequiredModelNeverSubstitutesAnotherEngine() {
        val all=catalog()
        for((language,id) in listOf("ru" to "gigaam-v3-int8","en" to "parakeet-v2-en-int8","de" to "whisper-large-v3-turbo-q8_0")) {
            val missing=all.filter { it.id!=id }
            assertNull(RecognitionRouting.recommended(missing,language))
            assertTrue(PackageLanguageSetup(language,listOf("en"),true,false).plan(missing,translationId=PackageCatalog.INDEX2B_ID).missingRecognition.contains(language))
            assertNull(RecognitionRouting.recommended(all.map { if(it.id==id)it.copy(unavailableReason="Unavailable") else it },language))
        }
    }
    @Test fun setupUsesTheSameThreeModelsWithoutDuplicates() {
        val setup=PackageLanguageSetup("ru",listOf("en","de","fr"),true,false).plan(catalog(),translationId=PackageCatalog.INDEX2B_ID)
        assertEquals(listOf("gigaam-v3-int8","parakeet-v2-en-int8","whisper-large-v3-turbo-q8_0"),setup.packages.filter { it.category==PackageCategory.RECOGNITION }.map { it.id })
    }
}
