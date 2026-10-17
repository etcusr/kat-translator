package org.openoffline.translator.android.packages

import android.content.res.AssetManager
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

enum class PackageCategory { TRANSLATION, RECOGNITION, VOICE, OCR }
enum class PackageKind { FILE, FILES, ARCHIVE, PIPER }
enum class PackagePhase { ABSENT, QUEUED, DOWNLOADING, PAUSED, VERIFYING, INSTALLING, INSTALLED, ERROR }

data class PackageStatus(
    val phase: PackagePhase = PackagePhase.ABSENT,
    val downloadedBytes: Long = 0,
    val totalBytes: Long = 0,
    val message: String? = null,
) {
    val progress: Float get() = if (totalBytes > 0) (downloadedBytes.toDouble() / totalBytes).toFloat().coerceIn(0f, 1f) else 0f
    val busy: Boolean get() = phase in setOf(PackagePhase.QUEUED, PackagePhase.DOWNLOADING, PackagePhase.VERIFYING, PackagePhase.INSTALLING)
}

data class OpusRouteSpec(val direction: String, val sources: Set<String>, val targets: Set<String>, val markers: Map<String, String>) {
    fun covers(source: String, target: String) = source != target && source in sources && target in targets
    fun route(target: String) = org.openoffline.translator.inference.OpusRoute(direction, markers[target] ?: "")
}
data class PackagePart(val id: String, val path: String, val remoteURL: String, val byteCount: Long, val sha256: String)
data class PackageEntry(val path: String, val byteCount: Long, val sha256: String)
data class OfflinePackage(
    val id: String,
    val title: String,
    val category: PackageCategory,
    val backend: String,
    val languages: Set<String>,
    val kind: PackageKind,
    val parts: List<PackagePart>,
    val files: List<PackageEntry>,
    val archiveRoot: String = id,
    val license: String = "",
    val sourceURL: String = "",
    val unavailableReason: String? = null,
    val runtimeLanguages: Map<String, String> = emptyMap(),
    val metadataSuffix: String? = null,
    val tokens: String? = null,
    /** OPUS model directories in this package and the language pairs each one translates. */
    val opusRoutes: List<OpusRouteSpec> = emptyList(),
) {
    val downloadBytes: Long get() = parts.sumOf { it.byteCount }
    val expandedBytes: Long get() = files.sumOf { it.byteCount }
    val unavailableReasonEnglish: String? get() = if (unavailableReason == null) null else when (backend) {
        "coreml" -> "This Core ML package requires Apple. Use Whisper on Android"
        "opus" -> "Downloading this pair is not available yet; install the files manually"
        "wayu" -> "The Wayu engine is not available on Android yet"
        "omnivoice" -> "The OmniVoice engine is not available on Android yet"
        else -> unavailableReason
    }
    fun supports(language: String) = language in languages
    fun runtimeLanguage(language: String) = runtimeLanguages[language] ?: language
}

/** The JSON assets are the same physical catalogs packaged by the Apple apps. */
object PackageCatalog {
    const val DEFAULT_TRANSLATION_BACKEND = "opus"
    const val DEFAULT_TRANSLATION_ID = "opus-mt-big-en-zle-int8"
    const val INDEX_ID = "index-translate-9b-q4km"
    const val INDEX_FILENAME = "Index-Translate-9B.Q4_K_M.gguf"
    const val INDEX2B_ID = "index-translate-2b-q4km"
    const val INDEX2B_FILENAME = "Index-Translate-2B.Q4_K_M.gguf"
    /** Fast multilingual model recommended beyond OPUS pairs; 9B stays the maximum-quality option. */
    const val MULTILINGUAL_BACKEND = "index2b"
    /** Index GGUF packages by translation backend: catalog symbol, package id, file name. */
    val INDEX_MODELS = mapOf("index" to Triple("indexTranslation", INDEX_ID, INDEX_FILENAME),
        "index2b" to Triple("indexTranslation2B", INDEX2B_ID, INDEX2B_FILENAME))
    fun load(assets: AssetManager): List<OfflinePackage> = load { name -> assets.open(name).bufferedReader().use { it.readText() } }

    internal fun load(read: (String) -> String): List<OfflinePackage> {
        val models = JSONObject(read("models.json")).getJSONArray("models").objects()
        val manifests = JSONArray(read("voice-manifests.json")).objects().associateBy { it.getString("id") }
        val capabilities = JSONObject(read("android-capabilities.json"))
        val whisper = capabilities.getJSONObject("whisper").stringMap()
        val omni = capabilities.getJSONObject("omnilingual").stringMap()
        val supertonic = capabilities.getJSONArray("supertonic").strings().toSet()
        val indexLanguages = capabilities.getJSONArray("index").strings().toSet()
        val ultraLanguages = capabilities.getJSONArray("ultra").strings().toSet()
        val packages = mutableListOf<OfflinePackage>()
        fun entry(value: JSONObject) = PackageEntry(value.getString("path"), value.getLong("byteCount"), value.getString("sha256"))
        fun part(value: JSONObject, path: String = value.optString("path", "model.bin")) = PackagePart(value.getString("id"), path,
            value.getString("remoteURL"), value.getLong("byteCount"), value.getString("sha256"))
        for (model in models) {
            val symbol = model.getString("symbol")
            if (symbol == "balineseTokens") continue // Owned by its voice; never independently deleted.
            val id = model.getString("id")
            val backend = when (symbol) {
                "indexTranslation" -> "index"
                "indexTranslation2B" -> "index2b"
                "turbo" -> "whisper"
                "omnilingual" -> "omnilingual"
                "supertonicVoice" -> "supertonic"
                "balineseVoice" -> "mms"
                "ocrRussian", "ocrEnglish" -> "ocr"
                else -> "piper"
            }
            val category = when (backend) {
                "index", "index2b" -> PackageCategory.TRANSLATION
                "whisper", "omnilingual" -> PackageCategory.RECOGNITION
                "ocr" -> PackageCategory.OCR
                else -> PackageCategory.VOICE
            }
            val languages = when (symbol) {
                "indexTranslation", "indexTranslation2B" -> indexLanguages
                "russianVoice", "irinaVoice", "ocrRussian" -> setOf("ru")
                "englishVoice", "lessacVoice", "ocrEnglish" -> setOf("en")
                "chineseVoice" -> setOf("zh")
                "balineseVoice" -> setOf("ban")
                "supertonicVoice" -> supertonic
                "turbo" -> whisper.keys
                "omnilingual" -> omni.keys
                else -> emptySet()
            }
            val manifest = manifests[id]
            val kind = when {
                symbol == "balineseVoice" -> PackageKind.FILES
                model.getString("remoteURL").endsWith(".tar.bz2") -> PackageKind.ARCHIVE
                else -> PackageKind.FILE
            }
            val parts = if (symbol == "balineseVoice") listOf(part(model, "model.onnx"), part(models.first { it.getString("symbol") == "balineseTokens" }, "tokens.txt")) else listOf(part(model))
            packages += OfflinePackage(id, model.getString("title"), category, backend, languages, kind, parts,
                manifest?.getJSONArray("files")?.objects()?.map(::entry) ?: parts.map { PackageEntry(it.path, it.byteCount, it.sha256) },
                manifest?.getString("archiveRoot") ?: id,
                license = when(symbol) { "supertonicVoice" -> "OpenRAIL-M"; "balineseVoice" -> "CC BY-NC 4.0"; "omnilingual" -> "Apache-2.0"; else -> "" },
                sourceURL = when(symbol) {
                    "indexTranslation" -> "https://huggingface.co/IndexTeam/Index-Translate-9B"
                    "indexTranslation2B" -> "https://huggingface.co/IndexTeam/Index-Translate-2B"
                    "supertonicVoice" -> "https://huggingface.co/Supertone/supertonic-3"
                    "balineseVoice" -> "https://huggingface.co/facebook/mms-tts-ban"
                    "chineseVoice" -> "https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/huayan/medium/MODEL_CARD"
                    "omnilingual" -> "https://huggingface.co/facebook/omniASR-CTC-300M-v2"
                    else -> ""
                },
                runtimeLanguages = when (backend) { "whisper" -> whisper; "omnilingual" -> omni; else -> emptyMap() })
        }
        for (voice in JSONArray(read("additional-voices.json")).objects()) {
            val id = voice.getString("id")
            val manifest = requireNotNull(manifests[id]) { "Missing voice manifest: $id" }
            val aliases = voice.optJSONObject("languageAliases")?.stringMap().orEmpty()
            val kind = when (voice.getString("kind")) { "archive" -> PackageKind.ARCHIVE; "piper" -> PackageKind.PIPER; else -> PackageKind.FILES }
            val backend = when { id.startsWith("omnivoice") -> "omnivoice"; id.startsWith("mms-") -> "mms"; else -> "piper" }
            packages += OfflinePackage(id, voice.getString("title"), PackageCategory.VOICE, backend,
                aliases.keys + voice.getString("language"), kind, voice.getJSONArray("parts").objects().map { part(it) },
                manifest.getJSONArray("files").objects().map(::entry), manifest.getString("archiveRoot"),
                voice.getString("license"), voice.getString("sourceURL"),
                runtimeLanguages = aliases, metadataSuffix = voice.optJSONObject("piperPreparation")?.getString("metadataSuffix"),
                tokens = voice.optJSONObject("piperPreparation")?.getString("tokens"))
        }
        val wayuParts = capabilities.getJSONArray("wayu").objects().map { part(it) }
        packages += OfflinePackage("wayu-prosody", "Тайский · Wayu Kokoro", PackageCategory.VOICE, "wayu", setOf("th"), PackageKind.FILES,
            wayuParts, wayuParts.map { PackageEntry(it.path, it.byteCount, it.sha256) }, license = "Apache-2.0",
            sourceURL = "https://huggingface.co/kunato/wayu-kokoro-thai-v1")
        val opus = JSONArray(read("opus-package.json")).objects().map { part(it) }
        packages += OfflinePackage("opus-mt-big-en-zle-int8", "OPUS-MT Big · EN ↔ RU / UK / BE", PackageCategory.TRANSLATION, "opus", setOf("en", "ru", "uk", "be"),
            PackageKind.FILES, opus, opus.map { PackageEntry(it.path, it.byteCount, it.sha256) }, license = "CC-BY-4.0",
            sourceURL = "https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-zle",
            opusRoutes = listOf(OpusRouteSpec("en-zle", setOf("en"), SLAVIC, mapOf("ru" to ">>rus<<", "uk" to ">>ukr<<", "be" to ">>bel<<")),
                OpusRouteSpec("zle-en", SLAVIC, setOf("en"), emptyMap())))
        // One package per OPUS-MT model direction; catalog order is routing priority after English.
        for (item in JSONArray(read("opus-direction-packages.json")).objects()) {
            val parts = item.getJSONArray("parts").objects().map { part(it) }
            val route = OpusRouteSpec(item.getString("direction"), item.getJSONArray("sources").strings().toSet(),
                item.getJSONArray("targets").strings().toSet(), item.getJSONObject("markers").stringMap())
            packages += OfflinePackage(item.getString("id"), "OPUS-MT Big · " + opusTitle(route), PackageCategory.TRANSLATION, "opus",
                route.sources + route.targets, PackageKind.FILES, parts, parts.map { PackageEntry(it.path, it.byteCount, it.sha256) },
                license = item.getString("license"), sourceURL = item.getString("sourceURL"), opusRoutes = listOf(route),
                unavailableReason = if (parts.any { "HOSTING-PENDING" in it.remoteURL }) "Скачивание этого направления пока недоступно; установите файлы вручную" else null)
        }
        for (recognizer in JSONArray(read("recognition-packages.json")).objects()) {
            val parts = recognizer.getJSONArray("parts").objects().map { part(it) }
            packages += OfflinePackage(recognizer.getString("id"), recognizer.getString("title"), PackageCategory.RECOGNITION, "coreml", ultraLanguages,
                PackageKind.FILES, parts, parts.map { PackageEntry(it.path, it.byteCount, it.sha256) },
                license = recognizer.getString("license"), sourceURL = recognizer.getString("sourceURL"),
                unavailableReason = "Пакет Core ML предназначен для Apple. На Android используйте Whisper")
        }
        for (model in JSONObject(read("android-asr.json")).getJSONArray("models").objects()) {
            val parts=model.getJSONArray("parts").objects().map { part(it) }
            packages += OfflinePackage(model.getString("id"),model.getString("title"),PackageCategory.RECOGNITION,
                model.getString("backend"),model.getJSONArray("languages").strings().toSet(),PackageKind.FILES,
                parts,parts.map { PackageEntry(it.path,it.byteCount,it.sha256) },license=model.getString("license"),sourceURL=model.getString("sourceURL"),
                runtimeLanguages=if(model.getString("backend")=="whisper")whisper else emptyMap())
        }
        for (model in JSONObject(read("android-ocr.json")).getJSONArray("models").objects()) {
            val p = part(model)
            packages += OfflinePackage(p.id, model.getString("title"), PackageCategory.OCR, "ocr-detector", setOf("ru", "en"),
                PackageKind.FILE, listOf(p), listOf(PackageEntry(p.path, p.byteCount, p.sha256)), license = model.getString("license"), sourceURL = model.getString("sourceURL"))
        }
        require(packages.map { it.id }.distinct().size == packages.size) { "Duplicate packages" }
        packages.forEach(::validate)
        return packages
    }

    private val SLAVIC = setOf("ru", "uk", "be")
    private fun opusTitle(route: OpusRouteSpec): String {
        fun side(languages: Set<String>) = languages.sorted().joinToString(" / ") { it.uppercase() }
        return side(route.sources) + " → " + side(route.targets)
    }
    /** First OPUS package (catalog order) that translates [source] to [target], with its route. */
    fun opusRoute(catalog: List<OfflinePackage>, source: String, target: String, available: (OfflinePackage) -> Boolean = { true }): Pair<OfflinePackage, org.openoffline.translator.inference.OpusRoute>? {
        for (pack in catalog) for (spec in pack.opusRoutes) if (spec.covers(source, target) && available(pack)) return pack to spec.route(target)
        return null
    }
    fun opusLanguages(catalog: List<OfflinePackage>): Set<String> = catalog.flatMap { pack -> pack.opusRoutes.flatMap { it.sources + it.targets } }.toSet()

    internal fun validate(pack: OfflinePackage) {
        require(pack.id.matches(Regex("[A-Za-z0-9_-]+")) && pack.parts.isNotEmpty() && pack.files.isNotEmpty())
        require(PackageIntegrity.safePath(pack.archiveRoot))
        require(pack.parts.map { it.id }.distinct().size == pack.parts.size)
        require(pack.parts.map { it.path }.distinct().size == pack.parts.size)
        require(pack.files.map { it.path }.distinct().size == pack.files.size)
        pack.parts.forEach {
            require(it.id.matches(Regex("[A-Za-z0-9_-]+")) && PackageIntegrity.safePath(it.path))
            require(URI(it.remoteURL).scheme == "https" && URI(it.remoteURL).host != null)
            require(it.byteCount > 0 && it.sha256.matches(Regex("[0-9a-f]{64}")))
        }
        pack.files.forEach { require(PackageIntegrity.safePath(it.path) && it.path != "receipt.json" && it.byteCount >= 0 && it.sha256.matches(Regex("[0-9a-f]{64}"))) }
    }
}

internal fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)
internal fun JSONArray.strings(): List<String> = (0 until length()).map(::getString)
internal fun JSONObject.stringMap(): Map<String, String> = keys().asSequence().associateWith(::getString)
