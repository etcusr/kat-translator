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
        assertTrue(all.single { it.backend=="parakeet" }.supports("ru"))
        assertEquals("gigaam-v3-int8",RecognitionRouting.recommended(all.reversed(),"ru")!!.id)
    }
    @Test fun everyOtherPublishedLanguageChoosesTheSameSharedParakeetPackage() {
        val all=catalog()
        val languages="bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro sk sl es sv uk".split(" ")
        assertEquals(languages.toSet()+"ru",all.single { it.backend=="parakeet" }.languages)
        for(language in languages)assertEquals(language,"parakeet-v3-int8",RecognitionRouting.recommended(all,language)!!.id)
        assertEquals(24,languages.size)
    }
    @Test fun unsupportedAndAutomaticLanguageAreNotFalselyAssigned() {
        val all=catalog()
        for(language in listOf("auto","zh","ja","ar","be","invalid"))assertNull(language,RecognitionRouting.recommended(all,language))
    }
    @Test fun readinessDoesNotChangeTheRequiredModelAndUnavailableBackendIsNotSelected() {
        val all=catalog()
        assertEquals("parakeet-v3-int8",RecognitionRouting.recommended(all,"en")!!.id)
        assertNull(RecognitionRouting.recommended(all.map { if(it.backend=="parakeet")it.copy(unavailableReason="Unavailable") else it },"en"))
        val setup=PackageLanguageSetup("ru",listOf("en","de","fr"),true,false).plan(all,translationId=PackageCatalog.INDEX_ID)
        assertEquals(listOf("gigaam-v3-int8","parakeet-v3-int8"),setup.packages.filter { it.category==PackageCategory.RECOGNITION }.map { it.id })
    }
}
