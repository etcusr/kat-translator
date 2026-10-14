package org.openoffline.translator.android.packages

/** User language scope is independent of model files; multilingual weights appear once.
 * Several "own" languages are allowed; every own language pairs with every target. */
data class PackageLanguageSetup(
    val primaryId: String,
    val targetIds: List<String>,
    val recognition: Boolean = true,
    val speech: Boolean = true,
    val extraPrimaryIds: List<String> = emptyList(),
) {
    val primaryIds: List<String> get() = (listOf(primaryId) + extraPrimaryIds).distinct()
    val languages: List<String> get() = (primaryIds + targetIds).distinct()
    val pairs: List<Pair<String, String>> get() = primaryIds.flatMap { p -> targetIds.filter { it !in primaryIds }.map { p to it } }
    fun withActivePair(source: String, target: String) = copy(targetIds = (targetIds + source + target).distinct().filter { it !in primaryIds })

    fun plan(
        catalog: List<OfflinePackage>,
        selectedVoices: Map<String, String> = emptyMap(),
        translationId: String = PackageCatalog.DEFAULT_TRANSLATION_ID,
        installedIDs: Set<String> = emptySet(),
    ): PackageSetupPlan {
        val selected = linkedMapOf<String, OfflinePackage>()
        val available = catalog.filter { it.unavailableReason == null || it.id in installedIDs }
        fun byId(id: String) = available.firstOrNull { it.id == id && it.category == PackageCategory.TRANSLATION }
        val explicit = byId(translationId)
        val missingTranslation = mutableListOf<String>()
        // The plan is valid when some translation package exists for the setup.
        val translation: OfflinePackage?
        fun opusFor(pairs: List<Pair<String, String>>): List<Pair<String, String>> {
            // Every OPUS model is one direction; a pair needs both. Returns pairs OPUS cannot cover.
            val uncovered = mutableListOf<Pair<String, String>>()
            for ((a, b) in pairs) {
                val routes = listOf(a to b, b to a).map { (x, y) -> (PackageCatalog.opusRoute(available, x, y) { it.id in installedIDs } ?: PackageCatalog.opusRoute(available, x, y))?.first }
                if (routes.any { it == null }) uncovered += a to b else routes.forEach { selected[it!!.id] = it }
            }
            return uncovered
        }
        when {
            translationId == AUTO_STRONG -> {
                translation = byId(PackageCatalog.INDEX_ID)?.also { selected[it.id] = it }
                missingTranslation += languages.filter { translation?.supports(it) != true }
            }
            translationId == AUTO_COMPACT -> {
                // Weak devices: OPUS for every pair it covers, Index 2B once for the rest.
                val uncovered = opusFor(pairs)
                val fallback = byId(PackageCatalog.INDEX2B_ID)
                if (uncovered.isNotEmpty() || pairs.isEmpty()) fallback?.let { selected[it.id] = it }
                missingTranslation += uncovered.flatMap { listOf(it.first, it.second) }.filter { fallback?.supports(it) != true }
                translation = selected.values.firstOrNull { it.category == PackageCategory.TRANSLATION }
            }
            explicit?.backend == "opus" -> {
                translation = explicit
                missingTranslation += opusFor(pairs).map { it.second }
                if (missingTranslation.isNotEmpty() || targetIds.isEmpty()) selected.putIfAbsent(explicit.id, explicit)
            }
            else -> {
                translation = explicit
                missingTranslation += languages.filter { explicit?.supports(it) != true }
                explicit?.let { selected[it.id] = it }
            }
        }
        val missingRecognition = mutableListOf<String>()
        val missingSpeech = mutableListOf<String>()
        for (language in languages) {
            if (recognition) {
                val candidates = available.filter { it.category == PackageCategory.RECOGNITION && it.supports(language) }
                val model = RecognitionRouting.recommended(available,language)
                    ?: candidates.firstOrNull { it.backend == "whisper" }
                    ?: candidates.firstOrNull { it.backend == "omnilingual" }
                if (model == null) missingRecognition += language else selected[model.id] = model
            }
            if (speech) {
                val candidates = available.filter { it.category == PackageCategory.VOICE && it.supports(language) }
                val voice = candidates.firstOrNull { it.id == selectedVoices[language] } ?: candidates.firstOrNull()
                if (voice == null) missingSpeech += language else selected[voice.id] = voice
            }
        }
        return PackageSetupPlan(selected.values.toList(), missingTranslation.distinct(), missingRecognition, missingSpeech,
            languages.size >= 2 && primaryId.isNotBlank() && translation != null && missingTranslation.isEmpty())
    }

    companion object {
        /** Automatic translation: Index 9B on strong devices, OPUS (+ Index 2B fallback) on others. */
        const val AUTO_STRONG = "auto:strong"
        const val AUTO_COMPACT = "auto:compact"
    }
}

data class PackageSetupPlan(
    val packages: List<OfflinePackage>,
    val missingTranslation: List<String>,
    val missingRecognition: List<String>,
    val missingSpeech: List<String>,
    val isValid: Boolean,
) {
    val ids: List<String> get() = packages.map { it.id }
    fun summary(states: Map<String, PackageStatus>): PackageSetupProgress {
        val total = packages.sumOf { it.downloadBytes }
        val received = packages.sumOf { pack ->
            val status = states[pack.id]
            if (status?.phase == PackagePhase.INSTALLED) pack.downloadBytes
            else (status?.downloadedBytes ?: 0L).coerceIn(0, pack.downloadBytes)
        }
        return PackageSetupProgress(total, received,
            isValid && packages.all { states[it.id]?.phase == PackagePhase.INSTALLED },
            packages.any { states[it.id]?.busy == true },
            packages.filter { states[it.id]?.phase == PackagePhase.ERROR }.map { it.id })
    }
}

data class PackageSetupProgress(val totalBytes: Long, val receivedBytes: Long, val ready: Boolean, val busy: Boolean, val failedIds: List<String>) {
    val remainingBytes: Long get() = totalBytes - receivedBytes
    val fraction: Float get() = if (totalBytes == 0L) 0f else (receivedBytes.toDouble() / totalBytes).toFloat()
}

/** Same selected-voice-per-language rule as language setup, including shared multilingual files. */
object PackageVoiceDownloads {
    fun plan(catalog: List<OfflinePackage>, selectedVoices: Map<String, String> = emptyMap()): PackageSetupPlan {
        val voices = catalog.filter { it.category == PackageCategory.VOICE && it.unavailableReason == null }
        val selected = voices.flatMap { it.languages }.distinct().mapNotNull { language ->
            voices.firstOrNull { it.id == selectedVoices[language] && it.supports(language) }
                ?: voices.firstOrNull { it.supports(language) }
        }.distinctBy { it.id }
        return PackageSetupPlan(selected, emptyList(), emptyList(), emptyList(), selected.isNotEmpty())
    }
}
