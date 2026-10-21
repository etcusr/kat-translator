package org.openoffline.translator.android.packages

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class PackageLanguageSetupTest {
    private fun catalog(): List<OfflinePackage> {
        var root = File(System.getProperty("user.dir"))
        while (!File(root, "assets/catalogs/models.json").exists()) root = root.parentFile ?: error("Repository root not found")
        return PackageCatalog.load { File(root, "assets/catalogs/$it").readText() }
    }

    @Test fun installedManualDirectionsDoNotRequireAnotherTranslationModel() {
        val catalog = catalog()
        val installed = setOf("opus-tc-big-zle-de-int8", "opus-tc-big-de-zle-int8")
        val setup = PackageLanguageSetup("ru", listOf("de"), false, false)
        val auto = setup.plan(catalog, translationId = PackageLanguageSetup.AUTO_COMPACT, installedIDs = installed)
        assertTrue(auto.isValid)
        assertEquals(installed, auto.ids.toSet())
        val manual = setup.plan(catalog, installedIDs = installed)
        assertTrue(manual.isValid)
        assertTrue(manual.missingTranslation.isEmpty())
    }

    @Test fun installedGroupDirectionWinsOverMissingSpecificDirection() {
        val catalog = catalog()
        val installed = setOf("opus-tc-big-zls-en-int8")
        val route = PackageCatalog.opusRoute(catalog, "bg", "en") { it.id in installed }
        assertEquals("opus-tc-big-zls-en-int8", route?.first?.id)
        assertEquals("zls-en", route?.second?.direction)
        assertNull(PackageCatalog.opusRoute(catalog, "bg", "en") { false })
    }

    @Test fun sharedRecognitionAndVoiceWeightsAppearOnceAcrossLanguages() {
        val catalog = catalog()
        val shared = catalog.single { it.backend == "supertonic" }
        val plan = PackageLanguageSetup("ru", listOf("en", "de", "en")).plan(catalog,
            mapOf("ru" to shared.id, "en" to shared.id, "de" to shared.id), translationId = PackageCatalog.INDEX_ID)
        assertTrue(plan.isValid)
        assertEquals(listOf("index", "gigaam", "supertonic", "parakeet", "whisper"), plan.packages.map { it.backend })
        assertTrue(plan.missingRecognition.isEmpty())
        assertTrue(plan.missingSpeech.isEmpty())
    }

    @Test fun disabledFeaturesAndDuplicateLanguageCannotCreateAFalseValidSetup() {
        val catalog = catalog()
        val plan = PackageLanguageSetup("ru", listOf("en"), false, false).plan(catalog)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID), plan.ids)
        assertFalse(PackageLanguageSetup("ru", listOf("ru")).plan(catalog).isValid)
        assertFalse(PackageLanguageSetup("invalid", listOf("en")).plan(catalog).isValid)
    }

    @Test fun androidDefaultUsesOpusWithoutFallingBackForUnsupportedPairs() {
        val catalog = catalog()
        assertEquals("opus", PackageCatalog.DEFAULT_TRANSLATION_BACKEND)
        val supported = PackageLanguageSetup("ru", listOf("en"), false, false).plan(catalog)
        assertTrue(supported.isValid)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID), supported.ids)
        val unsupported = PackageLanguageSetup("ru", listOf("ja"), false, false).plan(catalog)
        assertFalse(unsupported.isValid)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID), unsupported.ids)
        assertTrue(PackageLanguageSetup("ru", listOf("de"), false, false)
            .plan(catalog, translationId = PackageCatalog.INDEX_ID).isValid)
        val compact = PackageLanguageSetup("ru", listOf("de"), false, false).plan(catalog, translationId = PackageCatalog.INDEX2B_ID)
        assertTrue(compact.isValid)
        assertEquals(listOf(PackageCatalog.INDEX2B_ID), compact.ids)
    }

    @Test fun opusDirectionPackagesRouteEveryDeclaredPair() {
        val catalog = catalog()
        val directions = catalog.filter { it.backend == "opus" && it.id != PackageCatalog.DEFAULT_TRANSLATION_ID }
        assertTrue(directions.size >= 50)
        for (pack in directions) {
            val spec = pack.opusRoutes.single()
            assertEquals(setOf(spec.direction), pack.files.map { it.path.substringBefore('/') }.toSet())
            assertTrue(spec.markers.keys.all { it in spec.targets })
            assertTrue(spec.markers.values.all { it.matches(Regex(">>[a-z]{3}(_[A-Z][a-z]+)?<<")) })
        }
        // English stays on the original package; specific models win over group models.
        assertEquals(PackageCatalog.DEFAULT_TRANSLATION_ID, PackageCatalog.opusRoute(catalog, "en", "ru")!!.first.id)
        assertEquals(">>rus<<", PackageCatalog.opusRoute(catalog, "en", "ru")!!.second.marker)
        assertEquals("zle-de" to "", PackageCatalog.opusRoute(catalog, "ru", "de")!!.second.let { it.direction to it.marker })
        assertEquals(">>pol<<", PackageCatalog.opusRoute(catalog, "uk", "pl")!!.second.marker)
        assertEquals(">>ukr<<", PackageCatalog.opusRoute(catalog, "ru", "uk")!!.second.marker)
        assertEquals("ces_slk-en", PackageCatalog.opusRoute(catalog, "cs", "en")!!.second.direction)
        assertEquals("bg-en", PackageCatalog.opusRoute(catalog, "bg", "en")!!.second.direction)
        assertNull(PackageCatalog.opusRoute(catalog, "pt", "en"))
        assertNull(PackageCatalog.opusRoute(catalog, "de", "fr"))
        val hosted = catalog.map { if (it.backend == "opus") it.copy(unavailableReason = null) else it }
        val plan = PackageLanguageSetup("ru", listOf("en", "de", "pl"), false, false).plan(hosted)
        assertTrue(plan.isValid)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID, "opus-tc-big-zle-de-int8", "opus-tc-big-de-zle-int8",
            "opus-tc-big-zle-zlw-int8", "opus-tc-big-zlw-zle-int8"), plan.ids)
        assertFalse(PackageLanguageSetup("en", listOf("pt"), false, false).plan(hosted).isValid)
        assertFalse(PackageLanguageSetup("ru", listOf("ja"), false, false).plan(hosted).isValid)
    }

    @Test fun automaticPlanFollowsDeviceClassAndOwnLanguages() {
        val catalog = catalog()
        val strong = PackageLanguageSetup("ru", listOf("en", "ja"), false, false).plan(catalog, translationId = PackageLanguageSetup.AUTO_STRONG)
        assertTrue(strong.isValid)
        assertEquals(listOf(PackageCatalog.INDEX_ID), strong.ids)
        val compact = PackageLanguageSetup("ru", listOf("en", "ja"), false, false).plan(catalog, translationId = PackageLanguageSetup.AUTO_COMPACT)
        assertTrue(compact.isValid)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID, PackageCatalog.INDEX2B_ID), compact.ids)
        val englishOnly = PackageLanguageSetup("ru", listOf("en"), false, false).plan(catalog, translationId = PackageLanguageSetup.AUTO_COMPACT)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID), englishOnly.ids)
        // Two own languages: both pair with every target; neither is treated as a target.
        val own = PackageLanguageSetup("ru", listOf("en"), false, false, extraPrimaryIds = listOf("uk"))
        assertEquals(listOf("ru" to "en", "uk" to "en"), own.pairs)
        assertEquals(listOf(PackageCatalog.DEFAULT_TRANSLATION_ID), own.plan(catalog, translationId = PackageLanguageSetup.AUTO_COMPACT).ids)
        assertEquals(listOf("en"), own.withActivePair("uk", "en").targetIds)
    }

    @Test fun opusRequiresAvailableRuntimeAndEnglishCentricDirections() {
        val original = catalog()
        val opus = original.single { it.id == PackageCatalog.DEFAULT_TRANSLATION_ID }
        val disabled = original.map { if (it.id == opus.id) it.copy(unavailableReason = "not validated") else it }
        assertFalse(PackageLanguageSetup("ru", listOf("en")).plan(disabled, translationId = opus.id).isValid)
        val enabled = original.map { if (it.id == opus.id) it.copy(unavailableReason = null) else it }
        assertTrue(PackageLanguageSetup("en", listOf("ru", "uk", "be")).plan(enabled, translationId = opus.id).isValid)
        assertFalse(PackageLanguageSetup("ru", listOf("uk")).plan(enabled, translationId = opus.id).isValid)
    }

    @Test fun availableVoicesFallbackAndMissingCapabilitiesAreReported() {
        val catalog = catalog()
        val noVoices = catalog.filter { it.category != PackageCategory.VOICE }
        val plan = PackageLanguageSetup("ru", listOf("en")).plan(noVoices)
        assertEquals(listOf("ru", "en"), plan.missingSpeech)
        assertTrue(plan.isValid) // Voice limitations are visible without preventing text translation.
        val fallback = PackageLanguageSetup("ru", listOf("en")).plan(catalog, mapOf("en" to "retired-voice"))
        assertTrue(fallback.packages.any { it.category == PackageCategory.VOICE && it.supports("en") })
    }

    @Test fun progressUsesUniqueVerifiedPackagesAndClampsPartialBytes() {
        val plan = PackageLanguageSetup("ru", listOf("en"), false, false).plan(catalog())
        val id = plan.ids.single()
        val total = plan.packages.single().downloadBytes
        val half = plan.summary(mapOf(id to PackageStatus(PackagePhase.PAUSED, total / 2, total)))
        assertEquals(total - total / 2, half.remainingBytes)
        assertFalse(half.ready)
        val checking = plan.summary(mapOf(id to PackageStatus(PackagePhase.VERIFYING, total + 1, total)))
        assertEquals(total, checking.receivedBytes)
        assertFalse(checking.ready)
        assertTrue(checking.busy)
        assertTrue(plan.summary(mapOf(id to PackageStatus(PackagePhase.INSTALLED))).ready)
        assertEquals(listOf(id), plan.summary(mapOf(id to PackageStatus(PackagePhase.ERROR))).failedIds)
    }

    @Test fun activePairExtendsSavedSetupWithoutDuplicateDownloads() {
        val setup = PackageLanguageSetup("ru", listOf("en")).withActivePair("de", "ru")
        assertEquals(listOf("ru", "en", "de"), setup.languages)
    }

    @Test fun allVoicePlanDeduplicatesModelsAndHonorsSelectedVoice() {
        val catalog = catalog()
        val lessac = catalog.first { it.id.contains("lessac") }
        val plan = PackageVoiceDownloads.plan(catalog, mapOf("en" to lessac.id))
        assertTrue(lessac.id in plan.ids)
        assertEquals(plan.ids.distinct(), plan.ids)
        assertTrue(plan.packages.all { it.category == PackageCategory.VOICE && it.unavailableReason == null })
    }

    @Test fun packageMessagesFollowInterfaceLanguageAndKeepTechnicalDetails() {
        assertEquals("Importing file", PackageMessages.display("Импорт файла", false))
        assertEquals("Импорт файла", PackageMessages.display("Импорт файла", true))
        assertEquals("Server returned HTTP 429", PackageMessages.display("Сервер вернул HTTP 429", false))
        assertEquals("Not enough free space. Need another 123 MB", PackageMessages.display("Недостаточно свободного места. Нужно ещё 123 МБ", false))
        assertEquals("EACCES /package/file", PackageMessages.display("EACCES /package/file", false))
        assertNull(PackageMessages.display(null, false))
    }
}
