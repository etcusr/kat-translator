package org.openoffline.translator.android

import android.app.Application
import android.app.ActivityManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject
import org.openoffline.translator.inference.*
import org.openoffline.translator.android.packages.*
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

data class TranslationEntry(val id:String,val original:String,val translated:String,val target:String,val time:Long,
    val source:String="auto",val kind:String="text",val audio:String?=null,val image:String?=null,val originalAudio:String?=null)

data class MissingVoice(val language:String,val packageId:String,val workspace:String)
internal class MissingVoiceException(val request:MissingVoice):IllegalStateException()

const val AUTO_TRANSLATION="auto"
internal const val INDEX9B_GB=5.78
internal const val PROBE_THERMAL_MARGIN=0.7
internal const val PROBE_CPU_EFFICIENCY=0.8
internal const val PROBE_GPU_EFFICIENCY=1.0
internal const val STRONG_TOKENS_PER_SECOND=8.0
internal fun requireVoicePath(packageId:String,language:String,workspace:String,path:File?):File =
    path ?: throw MissingVoiceException(MissingVoice(language,packageId,workspace))

/** Native models have a single worker owner. UI state updates always return to main. */
class TranslatorState(app:Application):AndroidViewModel(app) {
    private val prefs=app.getSharedPreferences("kat",0)
    private val worker=Executors.newSingleThreadExecutor()
    private val voiceLoader=Executors.newSingleThreadExecutor()
    private val playbackEpoch=java.util.concurrent.atomic.AtomicLong()
    private val main=Handler(Looper.getMainLooper())
    private val cancelled=AtomicBoolean(false)
    private val closed=AtomicBoolean(false)
    private val translationResources = TranslationResources<IndexEngine, OpusEngine>()
    private var engine:IndexEngine?
        get()=translationResources.index
        set(value) { translationResources.index=value }
    private var opus:OpusEngine?
        get()=translationResources.opus
        set(value) { translationResources.opus=value }
    private var indexLease:AutoCloseable?
        get()=translationResources.indexLease
        set(value) { translationResources.indexLease=value }
    private var opusLease:AutoCloseable?
        get()=translationResources.opusLease
        set(value) { translationResources.opusLease=value }
    internal var opusLoadCount=0; private set
    internal var opusWeightLoadCount=0; private set
    private var opusDirection:String?=null
    var opusReady by mutableStateOf(false); private set
    val modelReady get()=if(effectiveModel=="opus")opusReady else ready
    private val recognitionPreparation=RecognitionPreparation()
    private var recognitionRevision by mutableIntStateOf(0)
    private var inForeground=true
    private fun recognitionKey()="$cameraSource|$recognitionPreference|${selectedRecognition()}"
    val recognitionReady get():Boolean { recognitionRevision;return recognitionPreparation.isReady(recognitionKey()) }
    val voiceReady get()=mode=="voice" && recognitionReady && (modelReady || (memorySaving && installed))
    var preparingModel by mutableStateOf(false); private set
    var verificationProgress by mutableStateOf<Float?>(null); private set
    var preparationSeconds by mutableStateOf<Double?>(null);private set
    private var automaticLoadAttempted=false
    private val media=OfflineMedia()
    private val systemSpeech=SystemSpeechRecognizer(app)
    private val mlKitOcr=MlKitOcr()
    val systemRecognitionAvailable get()=android.os.Build.VERSION.SDK_INT>=33 && android.speech.SpeechRecognizer.isOnDeviceRecognitionAvailable(getApplication())
    val packages=PackageDownloads.repository(app)
    var allowCellular by mutableStateOf(DownloadAccess.allowCellular(app));private set
    var languageSetup by mutableStateOf(PackageLanguageSetup(prefs.getString("setup.primary","ru")!!,prefs.getString("setup.targets","en")!!.split(",").filter { it.isNotBlank() },prefs.getBoolean("setup.recognition",true),prefs.getBoolean("setup.speech",true),prefs.getString("setup.extraPrimaries","")!!.split(",").filter { it.isNotBlank() }));private set
    fun changeAllowCellular(v:Boolean) { allowCellular=v;DownloadAccess.setAllowCellular(getApplication(),v) }
    fun saveLanguageSetup(setup:PackageLanguageSetup) {
        languageSetup=setup
        prefs.edit().putString("setup.primary",setup.primaryId).putString("setup.targets",setup.targetIds.joinToString(",")).putBoolean("setup.recognition",setup.recognition).putBoolean("setup.speech",setup.speech).putString("setup.extraPrimaries",setup.extraPrimaryIds.joinToString(",")).apply()
    }
    fun setupPlan(setup:PackageLanguageSetup=languageSetup)=setup.plan(packages.catalog,IndexLanguages.all.mapNotNull { lang -> selectedVoice(lang.id)?.let { lang.id to it } }.toMap(),
        if(translationModel==AUTO_TRANSLATION)(if(strongDevice)PackageLanguageSetup.AUTO_STRONG else PackageLanguageSetup.AUTO_COMPACT) else packageIdFor(translationModel),
        installedIDs=packages.catalog.filter { packages.installedPath(it.id)!=null }.map { it.id }.toSet())
    fun voiceDownloadPlan()=PackageVoiceDownloads.plan(packages.catalog,IndexLanguages.all.mapNotNull { lang -> selectedVoice(lang.id)?.let { lang.id to it } }.toMap())
    private val recorder by lazy {
        val model=File(app.noBackupFilesDir,"silero_vad.onnx")
        if(!model.isFile)app.assets.open("silero_vad.onnx").use { input -> model.outputStream().use { input.copyTo(it) } }
        PcmRecorder(model.path)
    }
    private val player=SpeechPlayer(app)
    internal val playbackGain get()=player.appliedGain
    internal val speechRuntimeTiming get()=media.lastSpeechTiming
    internal val speechPlaybackMetrics get()=player.metrics
    internal val recognitionLoads get()=media.recognitionLoads
    internal val recognitionRuntime get()=media.recognitionRuntime
    internal val voiceLoads get()=media.voiceLoads
    private val modelFile=File(app.getExternalFilesDir(null),"Index-Translate-9B.Q4_K_M.gguf")
    private val archiveDir=File(app.filesDir,"history").apply { mkdirs() }
    val exportDir=File(app.cacheDir,"exports").apply { mkdirs() }
    private var activeMode by mutableStateOf("voice")
    var mode:String
        get()=activeMode
        set(value) {
            if(value==activeMode)return
            require(value in setOf("voice","text","camera"))
            val leavingVoice=activeMode=="voice"
            activeMode=value
            if(leavingVoice) {
                if(recording)discardRecording()
                cancel();invalidateRecognition()
            }
            if(value=="voice" && modelReady) {
                if(inForeground) { if(busy)recognitionPreparation.defer(recognitionKey()) else prepare() }
            }
        }
    var previousMode="voice"
    // Each workspace owns its content, so voice replay/share never uses text-tab audio.
    private val inputs=mutableStateMapOf("text" to "", "voice" to "", "camera" to "")
    private val outputs=mutableStateMapOf("text" to "", "voice" to "", "camera" to "")
    var input:String get()=inputs[mode].orEmpty(); set(value) { inputs[mode]=value;translatedAudio.remove(mode);audioRevision++ }
    var output:String get()=outputs[mode].orEmpty(); set(value) { outputs[mode]=value }
    var source by mutableStateOf(prefs.getString("source","ru")!!)
    private var manualSource=prefs.getString("manualSource","ru")!!
    val cameraSource get()=if(source=="auto")manualSource.takeUnless { it=="auto" || it.isBlank() } ?: "ru" else source
    val currentSource get()=if(mode!="text")cameraSource else source
    var target by mutableStateOf(prefs.getString("target","en")!!)
    var detectedSource by mutableStateOf<String?>(null); private set
    var recognitionBackend by mutableStateOf<String?>(null); private set
    var busy by mutableStateOf(false); private set
    var ready by mutableStateOf(false); private set
    private fun modelInstalled(model:String)=when(model) { "opus" -> packages.catalog.any { it.opusRoutes.isNotEmpty() && packages.installedPath(it.id)!=null };"index" -> modelFile.isFile;else -> PackageCatalog.INDEX_MODELS[model]?.let { packages.installedPath(it.second)!=null } ?: false }
    val installed get()=if(translationModel==AUTO_TRANSLATION)listOf("index","index2b","opus").any(::modelInstalled) else modelInstalled(translationModel)
    /** Device class from the one-second memory probe: "strong" prefers Index 9B, "weak" prefers OPUS. */
    var deviceClass by mutableStateOf(prefs.getString("deviceClass",null)); private set
    var deviceBandwidth by mutableStateOf(prefs.getFloat("deviceBandwidthGbps",0f)); private set
    val strongDevice get()=deviceClass=="strong"
    /** Auto picks per language pair from installed models; explicit choices are used as is. */
    fun resolveModel(from:String,to:String):String? {
        if(translationModel!=AUTO_TRANSLATION)return translationModel
        val opusRoute=PackageCatalog.opusRoute(packages.catalog,from,to) { packages.installedPath(it.id)!=null }?.first
        val order=if(strongDevice)listOf("index","index2b") else listOf("opus","index2b","index")
        return order.firstOrNull { if(it=="opus")opusRoute!=null else modelInstalled(it) }
    }
    private val pairSource get()=if(currentSource=="auto")manualSource else currentSource
    val effectiveModel:String get()=resolveModel(pairSource,target) ?: if(translationModel==AUTO_TRANSLATION)(if(strongDevice)"index" else "opus") else translationModel
    /** Index 9B or Index 2B: both run the same GGUF runtime on Vulkan. */
    val indexModel get()=effectiveModel in PackageCatalog.INDEX_MODELS
    private fun packageIdFor(model:String)=PackageCatalog.INDEX_MODELS[model]?.second ?: OpusEngine.PACKAGE_ID
    private var engineModel:String?=null
    /** MTP measured faster only for 9B; Index 2B on Pixel 9 Pro was not faster with its draft block. */
    val mtpActive get()=effectiveModel=="index" && mtp
    var status by mutableStateOf(""); private set
    /** Index output is growing in place: the full-screen progress overlay gives way to a compact bar. */
    var streamingOutput by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var missingVoice by mutableStateOf<MissingVoice?>(null);private set
    private val timings=mutableStateMapOf<String,ProcessingTiming>()
    val timing get()=timings[mode]
    val seconds get()=timing?.translation
    @Volatile private var activeTiming:ProcessingTimer?=null
    @Volatile private var timingWorkspace:String?=null
    private fun addTiming(stage:ProcessingStage,elapsed:Double) {
        activeTiming?.add(stage,elapsed)
        val snapshot=activeTiming?.snapshot() ?: return
        val workspace=timingWorkspace ?: return
        ui { timings[workspace]=snapshot }
    }
    private inline fun <T> measure(stage:ProcessingStage,block:()->T):T {
        val start=System.nanoTime()
        try { return block() } finally { addTiming(stage,(System.nanoTime()-start)/1e9) }
    }
    private val firstTokens=mutableStateMapOf<String,Double?>()
    var firstToken:Double? get()=firstTokens[mode];private set(value) { firstTokens[mode]=value }
    var segmentIndex by mutableIntStateOf(0); private set
    var segmentCount by mutableIntStateOf(0); private set
    var interfaceLanguage by mutableStateOf(prefs.getString("interfaceLanguage","system")!!); private set
    val uiLanguage get()=UiStrings.language(interfaceLanguage, android.os.LocaleList.getDefault().let { list -> (0 until list.size()).map { list[it].toLanguageTag() } })
    fun text(ru:String,en:String?=null,vararg args:Any?)=UiStrings.text(ru,en,uiLanguage,*args)
    fun languageName(id:String)=IndexLanguages.byId[id]?.let { UiStrings.languageName(id,it.russian,it.english,uiLanguage) } ?: id
    var favorites by mutableStateOf(prefs.getStringSet("favoriteLanguages",setOf("ru","en"))!!.toSet()); private set
    var recordHistory by mutableStateOf(prefs.getBoolean("historyRecordText",true)); private set
    var recordAudio by mutableStateOf(prefs.getBoolean("historyRecordAudio",true)); private set
    var recordImages by mutableStateOf(prefs.getBoolean("historyRecordImages",true)); private set
    var showTechnical by mutableStateOf(prefs.getBoolean("showTechnicalInfo",false)); private set
    var memorySaving by mutableStateOf(prefs.getBoolean("memorySaving",false)); private set
    var mtp by mutableStateOf(prefs.getBoolean("mtpEnabled",true)); private set
    private var automaticSpeechVoice by mutableStateOf(prefs.getBoolean("automaticSpeechVoice",prefs.getBoolean("automaticSpeech",true)))
    private var automaticSpeechText by mutableStateOf(prefs.getBoolean("automaticSpeechText",false))
    val automaticSpeech get()=if(mode=="voice")automaticSpeechVoice else automaticSpeechText
    var translationModel by mutableStateOf(prefs.getString("translationModel",AUTO_TRANSLATION)!!); private set
    var wayuVoice by mutableStateOf(prefs.getString("wayuVoice","m_elderly_deep")!!); private set
    var automaticLoad by mutableStateOf(prefs.getBoolean("automaticModelLoad",true)); private set
    var recognitionPreference by mutableStateOf(prefs.getString("recognitionPreference","automatic")!!);private set
    var whisperDateTimeRepair by mutableStateOf(prefs.getBoolean("whisperDateTimeRepair",false)); private set
    var recordingPreprocessing by mutableStateOf(prefs.getBoolean("recordingPreprocessing",true)); private set
    var recordingVerification by mutableStateOf(prefs.getBoolean("recordingPreviewVerification",true)); private set
    var previewProcessing by mutableStateOf(false); private set
    var previewMessage by mutableStateOf<String?>(null); private set
    @Volatile private var recordingPreview:RecordingPreview?=null
    var recordingMode by mutableStateOf(prefs.getString("recordingMode","toggle")!!); private set
    var silenceSeconds by mutableIntStateOf(prefs.getInt("recordingSilenceSeconds",4)); private set
    var recordingMinutes by mutableIntStateOf(prefs.getInt("recordingLimitMinutes",10)); private set
    var speed by mutableFloatStateOf(prefs.getFloat("playbackSpeed",1f).takeIf { it in listOf(1f,1.25f,1.5f,2f) } ?: 1f); private set
    var historyCount by mutableIntStateOf(prefs.getInt("historyCount",100)); private set
    var historyDays by mutableIntStateOf(prefs.getInt("historyDays",30)); private set
    var audioCount by mutableIntStateOf(prefs.getInt("audioCount",10)); private set
    var imageCount by mutableIntStateOf(prefs.getInt("imageCount",20)); private set
    var audioDays by mutableIntStateOf(prefs.getInt("audioDays",30)); private set
    var imageDays by mutableIntStateOf(prefs.getInt("imageDays",30)); private set
    var history by mutableStateOf<List<TranslationEntry>>(emptyList()); private set
    var recording by mutableStateOf(false); private set
    var recordingPaused by mutableStateOf(false); private set
    var recordingMillis by mutableLongStateOf(0); private set
    var level by mutableFloatStateOf(0f); private set
    var playing by mutableStateOf(false); private set
    var playbackPaused by mutableStateOf(false); private set
    var playingFile by mutableStateOf<String?>(null); private set
    private var filePlayer:android.media.MediaPlayer?=null
    private var activePreview:String?=null
    private var playbackKey by mutableStateOf<String?>(null)
    private val previews=app.assets.list("VoicePreviews").orEmpty().toSet()
    var image by mutableStateOf<Bitmap?>(null); private set
    var cameraNotice by mutableStateOf<String?>(null); private set
    var ocrBlocks by mutableStateOf<List<OcrBlock>>(emptyList()); private set
    var translatedBlocks by mutableStateOf<List<String>>(emptyList()); private set
    private val translatedAudio=mutableStateMapOf<String,SpeechAudio>()
    private val historyTargets=java.util.concurrent.ConcurrentHashMap<String,Triple<String,String,String>>()
    private var originalAudio by mutableStateOf<SpeechAudio?>(null)
    var audioRevision by mutableIntStateOf(0); private set
    val hasTranslatedAudio get()=translatedAudio.containsKey(mode)
    val hasOriginalAudio get()=originalAudio!=null && mode=="voice"
    private var quietMillis=0L
    private var activeRecordingSilence=4
    private var activeRecordingHold=false
    private var activeRecordingLimit=10
    private var activeRecordingSource="auto"
    private var activeRecordingTarget="en"
    private var activeRecordingSpeak=true
    private var lastRecordingTick=0L
    init {
        restoreHistory(); exportDir.listFiles()?.forEach { it.delete() }
        viewModelScope.launch { packages.restored.first { it };tryAutomaticPrepare() }
    }
    fun tryAutomaticPrepare() {
        if(!automaticLoad || automaticLoadAttempted || !packages.restored.value || !installed || memorySaving || busy || recording || mode=="camera" || (modelReady && (mode!="voice" || recognitionReady)))return
        automaticLoadAttempted=true
        if(prefs.getString("unfinishedAutomaticModelLoad",null)==translationModel) {
            error=text("Предыдущая автозагрузка не завершилась. Подготовьте модель вручную или выберите другую.","The previous automatic load did not finish. Prepare the model manually or select another one.");return
        }
        prefs.edit().putString("unfinishedAutomaticModelLoad",translationModel).apply()
        prepare()
    }
    /** First-run device test, 3–5 s, no model files: CPU memory read bandwidth plus a decode-like
     * Q4_K matrix-vector run on the Vulkan GPU. Index decoding streams all weights per token, so
     * GB/s ÷ model size estimates tokens/s. Android keeps a 0.7 thermal margin for sustained use.
     * Calibration: Pixel 9 Pro (Index 9B Vulkan 3.9 tokens/s measured), Mac M3 Pro (CPU probe only). */
    var probing by mutableStateOf(false); private set
    var deviceGpuGbps by mutableStateOf(prefs.getFloat("deviceGpuGbps",0f)); private set
    var deviceEstimate9B by mutableStateOf(prefs.getFloat("deviceEstimate9B",0f)); private set
    fun runDeviceProbe() { if(probing || busy || recording)return;probing=true;worker.execute { probeDevice() } }
    private fun probeDevice() {
        releaseTranslation()
        val memory=try { IndexEngine.readBandwidthGbps(1.5) } catch(_:Throwable) { -1.0 }
        val gpu=try { IndexEngine.gpuMatvecGbps(2.0) } catch(_:Throwable) { -1.0 }
        val info=ActivityManager.MemoryInfo();(getApplication<Application>().getSystemService(Application.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
        val estimate=PROBE_THERMAL_MARGIN*maxOf(if(gpu>0)PROBE_GPU_EFFICIENCY*gpu/INDEX9B_GB else 0.0,if(memory>0)PROBE_CPU_EFFICIENCY*memory/INDEX9B_GB else 0.0)
        val value=if(estimate>=STRONG_TOKENS_PER_SECOND && info.totalMem>=11_500_000_000L)"strong" else "weak"
        prefs.edit().putString("deviceClass",value).putFloat("deviceBandwidthGbps",memory.toFloat()).putFloat("deviceGpuGbps",gpu.toFloat()).putFloat("deviceEstimate9B",estimate.toFloat()).apply()
        ui { deviceClass=value;deviceBandwidth=memory.toFloat();deviceGpuGbps=gpu.toFloat();deviceEstimate9B=estimate.toFloat();probing=false }
    }
    /** Sustained estimate after the thermal margin; 2B scales by file size. */
    fun estimatedTokensPerSecond(model:String)=if(deviceEstimate9B<=0f)null else deviceEstimate9B*(if(model=="index")1.0 else INDEX9B_GB/1.31)
    var setupCompleted by mutableStateOf(prefs.getBoolean("setup.completed",false)); private set
    fun markSetupCompleted() { setupCompleted=true;bool("setup.completed",true) }
    // Declared after the probe state it uses; Kotlin runs init blocks in declaration order.
    init { if(deviceClass==null || prefs.getFloat("deviceEstimate9B",0f)<=0f) { probing=true;worker.execute { probeDevice() } } }
    private fun bool(key:String,value:Boolean) { prefs.edit().putBoolean(key,value).apply() }
    fun changeInterfaceLanguage(value:String) { interfaceLanguage=value.takeIf { it in UiStrings.supportedLanguages } ?: "system"; prefs.edit().putString("interfaceLanguage",interfaceLanguage).apply() }
    fun toggleFavorite(id:String) { favorites=if(id in favorites)favorites-id else favorites+id;prefs.edit().putStringSet("favoriteLanguages",favorites).apply() }
    fun setHistory(v:Boolean) { recordHistory=v;bool("historyRecordText",v) }
    fun changeRecordAudio(v:Boolean) { recordAudio=v;bool("historyRecordAudio",v) }
    fun changeRecordImages(v:Boolean) { recordImages=v;bool("historyRecordImages",v) }
    fun selectTranslation(value:String) { if(busy || recording || value==translationModel)return;translationModel=value;automaticLoadAttempted=false;prefs.edit().putString("translationModel",value).apply();unload() }
    fun selectWayu(value:String) { translatedAudio.clear();audioRevision++;wayuVoice=value;prefs.edit().putString("wayuVoice",value).apply();stopPlayback() }
    fun setTechnical(v:Boolean) { showTechnical=v;bool("showTechnicalInfo",v) }
    fun changeAutomaticSpeech(v:Boolean) { if(mode=="voice") { automaticSpeechVoice=v;bool("automaticSpeechVoice",v) } else { automaticSpeechText=v;bool("automaticSpeechText",v) } }
    fun changeAutomaticLoad(v:Boolean) { automaticLoad=v;bool("automaticModelLoad",v);if(v && installed && (!modelReady || (mode=="voice" && !recognitionReady)))prepare() }
    fun changeMtp(v:Boolean) { mtp=v;bool("mtpEnabled",v);unload() }
    fun changeMemorySaving(v:Boolean) { memorySaving=v;bool("memorySaving",v);if(v && !busy)unload() }
    fun changeRecognitionPreference(v:String) { require(v in setOf("automatic","system","whisper"));invalidateRecognition();recognitionPreference=v;prefs.edit().putString("recognitionPreference",v).remove("recognitionModel").apply();audioRevision++ }
    fun changeWhisperDateTimeRepair(v:Boolean) { whisperDateTimeRepair=v;bool("whisperDateTimeRepair",v) }
    fun changeRecordingPreprocessing(v:Boolean) { recordingPreprocessing=v;bool("recordingPreprocessing",v) }
    fun changeRecordingVerification(v:Boolean) { recordingVerification=v;bool("recordingPreviewVerification",v) }
    fun changeRecordingMode(v:String) { recordingMode=v;prefs.edit().putString("recordingMode",v).apply() }
    fun setSilence(v:Int) { silenceSeconds=v.coerceIn(1,30);prefs.edit().putInt("recordingSilenceSeconds",silenceSeconds).apply() }
    fun setRecordingLimit(v:Int) { recordingMinutes=v.coerceIn(1,30);prefs.edit().putInt("recordingLimitMinutes",recordingMinutes).apply() }
    fun cycleSpeed() { val values=listOf(1f,1.25f,1.5f,2f);setPlaybackSpeed(values[(values.indexOf(speed)+1)%values.size]) }
    fun setPlaybackSpeed(value:Float) {
        require(value in listOf(1f,1.25f,1.5f,2f))
        speed=value;prefs.edit().putFloat("playbackSpeed",speed).apply()
        try {
            player.setSpeed(speed)
            filePlayer?.let { file -> file.playbackParams=android.media.PlaybackParams().setSpeed(speed).setPitch(1f);if(playbackPaused)file.pause() }
        } catch(e:Exception) { error=e.message }
    }
    fun setHistoryLimits(count:Int=historyCount,days:Int=historyDays,applyCleanup:Boolean=true) { historyCount=count;historyDays=days;prefs.edit().putInt("historyCount",count).putInt("historyDays",days).apply();if(applyCleanup) { pruneHistory();saveHistory() } }
    fun setMediaLimits(kind:String,count:Int,days:Int,applyCleanup:Boolean=true) {
        if(kind=="audio") { audioCount=count;audioDays=days } else { imageCount=count;imageDays=days }
        prefs.edit().putInt("${kind}Count",count).putInt("${kind}Days",days).apply();if(applyCleanup) { pruneHistory();saveHistory() }
    }
    fun chooseLanguage(id:String,from:Boolean) {
        if(mode!="text" && from && id=="auto")return
        if(mode=="camera")stopLiveCamera()
        if(from && id=="auto") { if(source!="auto")manualSource=source;source=id }
        else if(from) { if(id==target)target=if(source=="auto")manualSource else source;source=id;manualSource=id }
        else { if(id==currentSource) { source=target;manualSource=source };target=id }
        saveLanguages()
    }
    fun swap() { if(mode=="camera")stopLiveCamera();val old=if(mode!="text")cameraSource else if(source=="auto")detectedSource ?: manualSource else source;source=target;manualSource=source;target=old;saveLanguages() }
    private fun saveLanguages() {
        invalidateRecognition();missingVoice=null;stopPlayback();translatedAudio.clear();audioRevision++
        prefs.edit().putString("source",source).putString("target",target).putString("manualSource",manualSource).apply()
        if(mode=="camera" && image!=null && !busy) {
            cameraNotice=null;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]=""
            recognizeImage()
        }
    }
    fun clear() { if(busy)cancel();stopPlayback();input="";output="";error=null;missingVoice=null;timings.remove(mode);firstToken=null;translatedAudio.remove(mode);audioRevision++;if(mode=="voice") { originalAudio=null };if(mode=="camera") { image=null;ocrBlocks=emptyList();translatedBlocks=emptyList() } }
    fun clearOutput() { stopPlayback();output="";timings.remove(mode);firstToken=null;translatedAudio.remove(mode);audioRevision++ }
    fun reportError(message:String) { error=message }
    private fun ui(block:()->Unit) { main.post { if(!closed.get())block() } }
    private fun showFailure(error:Exception) {
        if(error is MissingVoiceException) { missingVoice=error.request;this.error=null }
        else this.error=error.message ?: text("Ошибка обработки","Processing failed")
    }
    private fun checkCancelled() { check(!cancelled.get() && !closed.get()) { text("Отменено","Cancelled") } }
    private fun work(initial:String,timedWorkspace:String?=null,continueTiming:Boolean=false,keepPreparedRecognition:Boolean=false,block:()->Unit) {
        if(busy || recording)return
        busy=true;error=null;missingVoice=null;status=initial;segmentCount=0;segmentIndex=0;cancelled.set(false)
        val previous=if(continueTiming && timedWorkspace!=null)timings[timedWorkspace] ?: ProcessingTiming() else ProcessingTiming()
        if(timedWorkspace!=null && !continueTiming) { timings.remove(timedWorkspace);firstTokens.remove(timedWorkspace) }
        worker.execute {
            timingWorkspace=timedWorkspace;activeTiming=if(timedWorkspace!=null)ProcessingTimer(previous) else null
            try { checkCancelled();block() } catch(e:Exception) { ui { if(!cancelled.get())showFailure(e) } }
            finally {
                val snapshot=activeTiming?.snapshot()
                if(snapshot!=null && timedWorkspace!=null)ui { timings[timedWorkspace]=snapshot }
                activeTiming=null;timingWorkspace=null
                if(memorySaving)releaseTranslation()
                if(!retainMediaModels()) {
                    media.releaseSpeech()
                    if(!keepPreparedRecognition || !recognitionReady)releaseRecognition()
                }
                ui {
                    busy=false;streamingOutput=false;preparingModel=false;verificationProgress=null
                    if(cancelled.get())status=text("Отменено","Cancelled")
                    if(recognitionPreparation.consumeDeferred(recognitionKey()) && inForeground && mode=="voice")prepare()
                } } }
    }
    private fun descriptor():JSONObject {
        val rows=JSONObject(getApplication<Application>().assets.open("models.json").bufferedReader().use { it.readText() }).getJSONArray("models")
        return (0 until rows.length()).map { rows.getJSONObject(it) }.first { it.getString("symbol")=="indexTranslation" }
    }
    private fun verify(file:File) {
        val spec=descriptor();check(file.length()==spec.getLong("byteCount")) { text("Установите Index в разделе «Модели».","Install Index in Models.") }
        val stamp="${file.length()}:${file.lastModified()}:${spec.getString("sha256")}"
        if(file==modelFile && prefs.getString("verifiedModel",null)==stamp)return
        ui { verificationProgress=0f };var received=0L;var previousPercent=-1
        val hash=MessageDigest.getInstance("SHA-256");val buffer=ByteArray(1024*1024)
        file.inputStream().use { stream -> while(true) { checkCancelled();val n=stream.read(buffer);if(n<0)break;hash.update(buffer,0,n);received+=n;val percent=(received*100/file.length()).toInt();if(percent!=previousPercent) { previousPercent=percent;val progress=received.toFloat()/file.length();ui { verificationProgress=progress } } } }
        check(hash.digest().joinToString("") { "%02x".format(it) }==spec.getString("sha256")) { text("Проверка Index не пройдена. Установите модель заново.","Index verification failed. Reinstall the model.") }
        if(file==modelFile)prefs.edit().putString("verifiedModel",stamp).apply()
    }
    private fun releaseTranslation() { engine?.close();engine=null;engineModel=null;indexLease?.close();indexLease=null;opus?.close();opus=null;opusDirection=null;opusLease?.close();opusLease=null;ui { ready=false;opusReady=false } }
    private fun ensureEngine(model:String=effectiveModel):IndexEngine {
        translationResources.useIndex();opusDirection=null;ui { opusReady=false }
        engine?.let { if(engineModel==model)return it;it.close();engine=null;indexLease?.close();indexLease=null;ui { ready=false } }
        ui { preparingModel=true;status=text("Проверка модели…","Checking model…") }
        val translationPackageId=packageIdFor(model)
        val path=if(model=="index") {
            if(packages.installedPath(PackageCatalog.INDEX_ID)==null)verify(modelFile);checkCancelled()
            if(packages.installedPath(PackageCatalog.INDEX_ID)!=null && indexLease==null)indexLease=packages.acquire(PackageCatalog.INDEX_ID)
            modelFile
        } else {
            // Receipt-verified package; no legacy unverified file path exists for Index 2B.
            val installedPath=packages.installedPath(translationPackageId) ?: error(text("Установите Index 2B в разделе «Модели».","Install Index 2B in Models."))
            if(indexLease==null)indexLease=packages.acquire(translationPackageId)
            installedPath
        }
        ui { verificationProgress=null;status=text("Загрузка модели…","Loading model…") }
        val loaded=try { measure(ProcessingStage.MODEL_LOAD) { IndexEngine.open(path.path,gpu=true,flash=true,mtp=model=="index" && mtp) } } catch(e:Exception) { indexLease?.close();indexLease=null;throw e }
        if(cancelled.get() || closed.get()) { loaded.close();error(text("Отменено","Cancelled")) }
        engine=loaded;engineModel=model;ui { ready=true;preparingModel=false };return loaded
    }
    fun prepare() {
        val voice=mode=="voice"
        if(!inForeground || busy || recording || (modelReady && (!voice || recognitionReady)) || !packages.restored.value)return
        automaticLoadAttempted=true;preparingModel=true
        val requestedKey=recognitionKey();val from=cameraSource
        val ticket=if(voice)recognitionPreparation.begin(requestedKey) else null
        recognitionRevision++
        work(text("Загрузка модели…","Loading model…"),keepPreparedRecognition=voice) {
            val start=System.nanoTime()
            try {
                val model=effectiveModel
                check(modelInstalled(model)) { text("Установите выбранную модель в разделе «Модели» или выберите другую.","Install the selected model in Models or choose another one.") }
                if(voice && memorySaving)releaseTranslation()
                else if(model=="opus")ensureOpus(pairSource,target,preparing=true) else ensureEngine(model)
                if(voice) {
                    checkCancelled()
                    try {
                        prepareRecognition(from);checkCancelled()
                        if(mode!="voice" || recognitionKey()!=requestedKey || !recognitionPreparation.complete(requireNotNull(ticket))) {
                            releaseRecognition()
                        } else ui { recognitionRevision++ }
                    } catch(e:Exception) { releaseRecognition();throw e }
                }
            } finally {
                val duration=(System.nanoTime()-start)/1e9;ui { preparationSeconds=duration }
                prefs.edit().remove("unfinishedAutomaticModelLoad").apply()
            }
        }
    }
    private fun ensureOpus(from:String,to:String,preparing:Boolean=false):Pair<OpusEngine,OpusRoute?> {
        // Each OPUS model direction is its own package. Preparation for a pair without an installed
        // package keeps the English package warm; translation itself reports the missing package.
        val found=PackageCatalog.opusRoute(packages.catalog,from,to) { packages.installedPath(it.id)!=null }
            ?: PackageCatalog.opusRoute(packages.catalog,from,to)
        val usable=found?.takeIf { !preparing || packages.installedPath(it.first.id)!=null }
        val packageId=usable?.first?.id ?: OpusEngine.PACKAGE_ID
        translationResources.useOpus();engineModel=null;ui { ready=false }
        var runtime=opus?.takeIf { it.packageId==packageId }
        if(runtime==null) {
            val title=packages.catalog.firstOrNull { it.id==packageId }?.title ?: "OPUS"
            val path=packages.installedPath(packageId) ?: error(text("Установите %@ в разделе «Модели».", "Install %@ in Models.", (title)))
            releaseTranslation();checkCancelled()
            ui { preparingModel=true;verificationProgress=null;status=text("Загрузка модели…","Loading model…") }
            val lease=packages.acquire(packageId)
            val loaded=try { OpusEngine.open(path.path,packageId) } catch(e:Exception) { lease.close();throw e }
            if(cancelled.get() || closed.get()) { loaded.close();lease.close();checkCancelled() }
            opus=loaded;opusLease=lease;opusLoadCount++;runtime=loaded
        }
        val route=usable?.second
        if(route!=null && opusDirection!=route.direction) {
            ui { preparingModel=true;opusReady=false;status=text("Загрузка модели…","Loading model…") }
            measure(ProcessingStage.MODEL_LOAD) { runtime.prepare(route) };checkCancelled();opusDirection=route.direction;opusWeightLoadCount++
        }
        ui { opusReady=true;preparingModel=false }
        return runtime to route
    }
    private fun translateParts(text:String,language:String,from:String=currentSource,progress:((String)->Unit)?=null):String {
        val model=resolveModel(from,language) ?: error(text("Для этой пары не установлена модель перевода. Откройте «Настроить языки и загрузку».","No translation model is installed for this pair. Open language setup."))
        if(model=="opus")return translateOpus(text,from,language)
        val runtime=ensureEngine(model);checkCancelled();ui { status=this.text("Подготовка текста…","Preparing text…") }
        val parts=TextSegments.split(text) { part -> checkCancelled();IndexRequest.fits(runtime.tokens(IndexRequest(part,language)).size,runtime.sourceTokenCount(part)) }
        ui { segmentCount=parts.size;segmentIndex=0 }
        val result=StringBuilder();val start=System.nanoTime()
        parts.forEachIndexed { index,part ->
            checkCancelled();ui { segmentIndex=index+1;status=text("Перевожу","Translating")+(if(parts.size>1)" · ${index+1}/${parts.size}" else "") }
            val separator=if(result.isEmpty())"" else if(part.startsWith("\n"))"\n" else " "
            val committed=result.toString()
            val poller=progress?.let { publish -> PartialPoller(main,{ runtime.partial() }) { if(it.isNotBlank())publish(committed+separator+it) } }
            val translated=try { runtime.translate(IndexRequest(part,language)) } finally { poller?.stop() }
            when(translated) {
                is TranslationResult.Success -> { if(index==0)ui { firstToken=translated.firstTokenSeconds };result.append(separator);result.append(translated.text);progress?.invoke(result.toString()) }
                TranslationResult.Cancelled -> error(text("Отменено","Cancelled"))
                TranslationResult.Limit -> error(text("Модель остановилась по лимиту. Результат не сохранён.","Model reached its output limit. Result was not saved."))
                else -> error(text("Не удалось выполнить перевод.","Translation failed."))
            }
        }
        addTiming(ProcessingStage.TRANSLATION,(System.nanoTime()-start)/1e9);return result.toString()
    }
    fun translate() {
        if(input.isBlank() || busy)return
        val original=input;val language=target;val from=currentSource;val workspace=mode
        outputs[workspace]="";translatedAudio.remove(workspace);audioRevision++;timings.remove(mode);firstToken=null
        work(text("Подготовка перевода…","Preparing translation…"),workspace) { finishTranslation(original,from,language,workspace) }
    }
    private fun finishTranslation(original:String,from:String,language:String,workspace:String,preparedTranslation:String?=null,speak:Boolean=automaticSpeech) {
        val resolved=if(from=="auto")detectLanguage(original) else from
        ui { if(from=="auto")detectedSource=resolved }
        val retain=retainMediaModels()
        if(!retain) { releaseRecognition();media.releaseSpeech() }
        val preload=if(speak && retain)preloadVoice(language) else null
        // Finished sentences are spoken while Index writes the rest (Piper family and Supertonic; OmniVoice
        // and Wayu are too large to run beside Index). Synthesis runs on the voice thread after the preload.
        val feed=if(speak && preparedTranslation==null && !memorySaving && streamableVoice(language))SentenceFeed() else null
        val streamKey="$workspace:target:streaming"
        val speechJob=feed?.let { sentences -> voiceLoader.submit(java.util.concurrent.Callable { synthesizeAndPlay(sentences.sentences(),language,streamKey,false,startSeconds=2) }) }
        val stream:(String)->Unit={ partial -> feed?.offer(partial);ui { if(!cancelled.get()) { outputs[workspace]=partial;streamingOutput=true } } }
        val translated=try { TranslationRouting.translate(original,resolved ?: from,language) { preparedTranslation ?: translateParts(original,language,resolved ?: from,stream) } }
            catch(e:Exception) { feed?.abort();if(feed!=null)ui { stopPlayback() };ui { if(streamingOutput)outputs[workspace]="";streamingOutput=false };throw e }
            finally { if(feed==null)preload?.get() }
        if(cancelled.get())feed?.abort() else feed?.finish(translated)
        checkCancelled()
        ui { if(!cancelled.get()) { inputs[workspace]=original;outputs[workspace]=translated;status=text("Готово","Done") } }
        // Commit the completed translation before optional speech, as on iOS.
        val historyId=archive(original,translated,resolved ?: from,language,workspace,null)
        var speech:SpeechAudio?=null
        if(speak) {
            val finalKey="$workspace:target:${translated.hashCode()}"
            try {
                speech=if(speechJob!=null) {
                    ui { if(playbackKey==streamKey)playbackKey=finalKey }
                    try { speechJob.get().also { ui { if(playbackKey==streamKey)playbackKey=finalKey } } }
                    catch(e:java.util.concurrent.ExecutionException) { throw (e.cause as? Exception) ?: e }
                } else synthesizeAndPlay(translated,language,finalKey)
                checkCancelled();val completed=speech;ui { if(!cancelled.get()) { translatedAudio[workspace]=completed;audioRevision++ } }
            }
            catch(e:Exception) { ui { if(!cancelled.get())showFailure(e) } }
        }
        checkCancelled()
        if(recordAudio)speech?.let { if(historyId==null || !appendHistorySpeech(historyId,it))archive(original,translated,resolved ?: from,language,workspace,it) }
    }
    private fun translateOpus(content:String,from:String,to:String):String {
        require(PackageCatalog.opusRoute(packages.catalog,from,to)!=null) { text("Для этой пары языков нет модели OPUS. Выберите другую пару или Index.","No OPUS model covers this language pair. Select another pair or Index.") }
        val (runtime,found)=ensureOpus(from,to)
        val route=checkNotNull(found)
        val start=System.nanoTime()
        return try {
                val parts=OpusSegments.split(content) { checkCancelled();runtime.tokens(it,route)<=OpusEngine.MAX_INPUT_TOKENS }
                ui { segmentCount=parts.size;segmentIndex=0;firstToken=null }
                fun run(part:String):String { checkCancelled();return when(val result=runtime.translate(part,route)) {
                    is TranslationResult.Success->result.text
                    TranslationResult.Limit->{ val (a,b)=OpusSegments.bisect(part);run(a)+" "+run(b) }
                    TranslationResult.Cancelled->error(text("Отменено","Cancelled"))
                    else->error(text("Ошибка перевода OPUS.","OPUS translation failed."))
                } }
                parts.mapIndexed { index,part -> ui { segmentIndex=index+1;status=text("Перевожу","Translating")+" · ${index+1}/${parts.size}" };run(part) }.joinToString(" ")
            } finally { addTiming(ProcessingStage.TRANSLATION,(System.nanoTime()-start)/1e9) }
    }
    private fun detectLanguage(text:String):String?=try {
        val manager=getApplication<Application>().getSystemService(android.view.textclassifier.TextClassificationManager::class.java)
        val result=manager.textClassifier.detectLanguage(android.view.textclassifier.TextLanguage.Request.Builder(text.take(10000)).build())
        if(result.localeHypothesisCount>0 && result.getConfidenceScore(result.getLocale(0))>=.5f)result.getLocale(0).language.takeIf { it in IndexLanguages.byId } else null
    } catch(_:Exception) { null }
    fun cancel() { recognitionPreparation.cancelDeferred();if(busy) { stopPlayback();cancelled.set(true);status=text("Отменяю…","Cancelling…");systemSpeech.cancel();mlKitOcr.cancel();engine?.cancel();opus?.cancel();media.cancel() } }
    private fun releaseRecognition(invalidate:Boolean=true) {
        if(invalidate)recognitionPreparation.invalidate(clearDeferred=false)
        media.releaseRecognition();systemSpeech.releasePrepared()
        ui { recognitionRevision++ }
    }
    private fun invalidateRecognition() {
        recognitionPreparation.invalidate();recognitionRevision++
        media.cancel();systemSpeech.cancel()
        worker.execute { releaseRecognition(invalidate=false) }
    }
    fun unload() { if(busy)return;recognitionPreparation.invalidate();recognitionRevision++;worker.execute { releaseTranslation();releaseRecognition(invalidate=false);media.releaseSpeech() } }
    fun trimMemory() { if(!closed.get()) { recognitionPreparation.invalidate();recognitionRevision++;worker.execute { releaseRecognition(invalidate=false);media.releaseSpeech() } } }
    private fun retainMediaModels():Boolean {
        val info=ActivityManager.MemoryInfo()
        getApplication<Application>().getSystemService(ActivityManager::class.java).getMemoryInfo(info)
        return MediaCachePolicy.retain(info.totalMem,info.availMem,info.threshold,memorySaving || info.lowMemory)
    }
    // Android 14+ no longer delivers RUNNING_LOW/onLowMemory; also sample idle headroom.
    private val memoryTicker=object:Runnable { override fun run() {
        if(closed.get())return
        if(!busy && !recording && !previewProcessing && !retainMediaModels()) {
            val info=ActivityManager.MemoryInfo();getApplication<Application>().getSystemService(ActivityManager::class.java).getMemoryInfo(info)
            if(!recognitionReady || info.lowMemory || info.availMem<info.threshold*2)trimMemory()
        }
        main.postDelayed(this,15_000)
    } }
    fun foreground() { inForeground=true;main.removeCallbacks(memoryTicker);main.postDelayed(memoryTicker,15_000) }
    /** Finish releasing native mappings first, then start the FGS on main only while the
     * originating screen is still visible. Leaving the app cancels this handoff. */
    private fun packageAction(visible:()->Boolean,launch:()->Unit) {
        if(busy || recording)return
        busy=true;cancelled.set(false);error=null;status=text("Подготовка моделей…","Preparing models…")
        worker.execute {
            try {
                releaseTranslation();releaseRecognition();media.releaseSpeech()
                ui {
                    busy=false
                    if(cancelled.get() || !visible()) {
                        error=text("Вернитесь в приложение и повторите действие.","Return to the app and try again.")
                    } else {
                        try { launch() } catch(e:Exception) { error=e.message ?: text("Не удалось запустить загрузку.","Could not start the download.") }
                    }
                }
            } catch(e:Exception) { ui { busy=false;error=e.message } }
        }
    }
    fun startPackages(ids:List<String>,visible:()->Boolean,afterStart:()->Unit={}) { packageAction(visible) { PackageDownloads.startAll(getApplication(),ids);afterStart() } }
    fun startPackage(id:String,visible:()->Boolean) {
        packageAction(visible) { PackageDownloads.start(getApplication(),id) }
    }
    fun importPackage(id:String,uri:Uri,visible:()->Boolean) {
        packageAction(visible) { PackageDownloads.importFile(getApplication(),id,uri) }
    }
    fun removePackage(id:String) { if(busy || recording)return;worker.execute { releaseTranslation();releaseRecognition();media.releaseSpeech();packages.remove(id) } }
    fun selectedVoice(language:String):String? {
        audioRevision
        prefs.getString("voice.$language",null)?.let { return it }
        val voices=packages.catalog.filter { it.category==PackageCategory.VOICE && it.unavailableReason==null && it.supports(language) }
        // Irina is the default Russian voice; without an explicit choice an already installed earlier default is kept.
        val preferred=voices.sortedBy { if(language=="ru" && it.id==PackageVoiceDefaults.RUSSIAN) 0 else 1 }
        val installed=packages.states.value
        return (preferred.firstOrNull()?.takeIf { installed[it.id]?.phase==PackagePhase.INSTALLED }
            ?: preferred.firstOrNull { installed[it.id]?.phase==PackagePhase.INSTALLED } ?: preferred.firstOrNull())?.id
    }
    fun selectVoice(language:String,id:String) { if(selectedVoice(language)!=id)worker.execute { media.releaseSpeech() };missingVoice=null;stopPlayback();translatedAudio.clear();prefs.edit().putString("voice.$language",id).apply();audioRevision++ }
    fun selectedRecognition():String? { audioRevision;return prefs.getString("recognitionModel",null) }
    fun selectRecognition(id:String) { if(prefs.getString("recognitionModel",null)!=id)invalidateRecognition();recognitionPreference="automatic";prefs.edit().putString("recognitionPreference","automatic").putString("recognitionModel",id).apply();audioRevision++ }
    private fun installedPackage(category:PackageCategory,language:String,preferred:String?=null):Pair<OfflinePackage,File> {
        val candidates=packages.catalog.filter { it.category==category && (category!=PackageCategory.RECOGNITION || recognitionPreference!="whisper" || it.backend=="whisper") && it.unavailableReason==null && it.backend!="ocr-detector" && (language=="auto" || it.supports(language) || it.languages.isEmpty()) && !(it.backend=="omnilingual" && language=="auto") }
        val selected=if(preferred!=null)candidates.firstOrNull { it.id==preferred }
            else if(category==PackageCategory.RECOGNITION)candidates.firstOrNull { it.backend=="whisper" } ?: candidates.firstOrNull()
            else candidates.firstOrNull()
        val path=selected?.let { packages.installedPath(it.id) }
        if(selected==null || path==null)error(text("Установите выбранную модель в разделе «Модели» или выберите другую.","Install the selected model in Models or choose another one."))
        return selected to path
    }
    private fun findFile(root:File,predicate:(File)->Boolean):File=root.walkTopDown().firstOrNull { it.isFile && predicate(it) } ?: error(text("В пакете отсутствует нужный файл.","Required file is missing from the package."))
    private fun preloadVoice(language:String):java.util.concurrent.Future<*> {
        val selected=selectedVoice(language)
        val pack=packages.catalog.firstOrNull { it.id==selected && it.category==PackageCategory.VOICE && it.supports(language) && it.unavailableReason==null && it.backend in setOf("piper","vits","mms") }
        val path=pack?.let { packages.installedPath(it.id) }
        return voiceLoader.submit {
            try {
                if(pack!=null && path!=null && !cancelled.get() && !closed.get())packages.acquire(pack.id).use {
                    val model=findFile(path) { it.extension=="onnx" && !it.name.contains("encoder") }
                    val tokens=findFile(path) { it.name=="tokens.txt" }
                    val data=if(pack.backend=="mms")"" else path.walkTopDown().firstOrNull { it.isDirectory && it.name=="espeak-ng-data" }?.path ?: bundledEspeak().path
                    if(!cancelled.get() && !closed.get())media.preloadPiper(model.path,tokens.path,data)
                }
            } catch(_:Exception) { /* The ordinary synthesis path reports an unavailable voice. */ }
        }
    }
    private fun streamableVoice(language:String):Boolean {
        val selected=selectedVoice(language)
        return packages.catalog.any { it.id==selected && it.category==PackageCategory.VOICE && it.supports(language) && it.unavailableReason==null && it.backend in setOf("piper","vits","mms","supertonic") }
    }
    private fun synthesizeAndPlay(text:String,language:String,key:String):SpeechAudio=synthesizeAndPlay(sequenceOf(text),language,key,true)
    /** [texts] may block until the next translated sentence exists; all pieces form one utterance. */
    private fun synthesizeAndPlay(texts:Sequence<String>,language:String,key:String,showStatus:Boolean,startSeconds:Int=4):SpeechAudio {
        val epoch=playbackEpoch.get()
        var stream:SpeechStream?=null // Accessed only by FIFO main-thread posts.
        val opening=SpeechStartBuffer(startSeconds)
        ui { if(playbackEpoch.get()==epoch)clearPlayback() }
        fun enqueue(chunk:SpeechAudio) {
            ui {
                if(!cancelled.get() && playbackEpoch.get()==epoch)try {
                    if(stream==null) {
                        stream=player.startStream(chunk.sampleRate,speed);playbackKey=key;playing=true;playbackPaused=false;main.post(playbackTicker)
                    }
                    stream?.offer(chunk.samples)
                } catch(e:Exception) { stopPlayback();error=e.message }
            }
        }
        return try {
            val audio=measure(ProcessingStage.SYNTHESIS) { synthesizeImpl(texts,language,showStatus) { chunk ->
                opening.accept(chunk).forEach(::enqueue)
            } }
            checkCancelled();opening.finish().forEach(::enqueue)
            ui { if(playbackEpoch.get()==epoch)stream?.finish() }
            audio
        } catch(e:Exception) {
            ui { if(playbackEpoch.get()==epoch)stopPlayback() };throw e
        }
    }
    private fun synthesizeImpl(texts:Sequence<String>,language:String,showStatus:Boolean,onChunk:(SpeechAudio)->Unit):SpeechAudio {
        checkCancelled()
        val selected=selectedVoice(language)
        val pack=packages.catalog.firstOrNull { it.id==selected && it.category==PackageCategory.VOICE && it.supports(language) && it.unavailableReason==null }
            ?: error(this.text("Для выбранного языка нет доступной озвучки. Выберите другой голос в настройках.","No voice is available for this language. Choose another voice in settings."))
        val path=requireVoicePath(pack.id,language,mode,packages.installedPath(pack.id))
        if(showStatus)ui { status=this.text("Подготовка озвучки…","Preparing speech…") }
        if(memorySaving) { releaseTranslation();releaseRecognition() }
        checkCancelled()
        return packages.acquire(pack.id).use {
            val normalizer=StreamingSpeechLoudness()
            val chunks=mutableListOf<SpeechAudio>()
            fun deliver(raw:SpeechAudio) {
                checkCancelled()
                normalizer.accept(raw)?.let { chunks+=it;onChunk(it) }
            }
            for(part in texts.flatMap { TextSegments.split(it) { piece -> piece.length<=1500 } }) {
                checkCancelled()
                val spoken=if(language=="ru" && pack.backend !in setOf("omnivoice","wayu"))RussianSpeechText.expandOrdinals(part) else part
                if(pack.backend in setOf("omnivoice","wayu"))media.releaseSpeech()
                when(pack.backend) {
                    "omnivoice" -> deliver(media.synthesizeOmniVoice(path.path,spoken,pack.runtimeLanguage(language)))
                    "wayu" -> deliver(media.synthesizeWayu(WayuAssets.prepare(getApplication()),path.path,spoken,wayuVoice))
                    "supertonic" -> { val config=findFile(path) { it.name=="tts.json" };deliver(media.synthesizeSupertonic(config.parent!!,spoken,pack.runtimeLanguage(language))) }
                    else -> {
                        val model=findFile(path) { it.extension=="onnx" && !it.name.contains("encoder") }
                        val tokens=findFile(path) { it.name=="tokens.txt" }
                        val data=if(pack.backend=="mms")"" else path.walkTopDown().firstOrNull { it.isDirectory && it.name=="espeak-ng-data" }?.path ?: bundledEspeak().path
                        val prepared=if(pack.backend=="mms")MmsSpeechText.prepare(spoken,tokens.readText(),pack.runtimeLanguage(language)) else spoken
                        // The final native aggregate is validated, never enqueued a second time.
                        media.synthesizePiper(model.path,tokens.path,data,prepared) { samples,rate -> deliver(SpeechAudio(samples,rate)) }
                    }
                }
            }
            normalizer.finish()?.let { chunks+=it;onChunk(it) }
            check(chunks.isNotEmpty()) { "Empty speech stream" }
            val rate=chunks.first().sampleRate;check(chunks.all { it.sampleRate==rate })
            val samples=FloatArray(chunks.sumOf { it.samples.size });var offset=0
            chunks.forEach { it.samples.copyInto(samples,offset);offset+=it.samples.size }
            SpeechAudio(samples,rate)
        }
    }
    private fun bundledEspeak():File {
        val target=File(getApplication<Application>().noBackupFilesDir,"espeak-ng-data")
        if(File(target,".complete").isFile)return target
        val assets=getApplication<Application>().assets
        fun copyAsset(path:String,file:File) {
            checkCancelled();val children=assets.list(path).orEmpty()
            if(children.isEmpty()) { file.parentFile?.mkdirs();assets.open(path).use { input -> file.outputStream().use { input.copyTo(it) } } }
            else { file.mkdirs();children.forEach { copyAsset("$path/$it",File(file,it)) } }
        }
        copyAsset("espeak-ng-data",target);File(target,".complete").writeText("1");return target
    }

    fun isTextPlaying(original:Boolean=false):Boolean {
        val key=if(original && mode=="voice")"voice.recording"
            else "$mode:${if(original)"source" else "target"}:${(if(original)input else output).hashCode()}"
        return playing && playbackKey==key
    }
    fun readText(original:Boolean=false) {
        // Automatic speech may start before the translation worker finishes bookkeeping.
        if(isTextPlaying(original)) { stopPlayback();return }
        if(busy || recording)return
        if(original && mode=="voice") { playOriginal();return }
        val workspace=mode;val content=if(original)input else output;val language=if(original) { if(currentSource=="auto")detectedSource else currentSource } else target
        if(content.isBlank())return
        val key="$workspace:${if(original)"source" else "target"}:${content.hashCode()}"
        if(language==null) { error=text("Для озвучки оригинала выберите язык.","Select the source language to read the original.");return }
        if(!original && translatedAudio[workspace]!=null) { playSpeech(translatedAudio.getValue(workspace),key);return }
        work(text("Подготовка озвучки…","Preparing speech…"),workspace,continueTiming=true) {
            val speech=synthesizeAndPlay(content,language,key);checkCancelled()
            archiveManualSpeech(content,language,workspace,original,speech)
            ui { if(!cancelled.get() && !original) { translatedAudio[workspace]=speech;audioRevision++ } }
        }
    }
    fun playOriginal() {
        if(mode!="voice" || busy || recording)return
        val original=originalAudio ?: return
        if(playing && playbackKey=="voice.recording") { stopPlayback();return }
        playSpeech(original,"voice.recording",normalizeVolume=true)
    }
    private val playbackTicker=object:Runnable { override fun run() {
        if(filePlayer==null && playing && !player.isPlaying) { player.metrics?.failure?.let { error=it };playing=false;playbackPaused=false;return }
        if(playing)main.postDelayed(this,150)
    } }
    private fun playSpeech(audio:SpeechAudio,key:String?=null,normalizeVolume:Boolean=false) {
        stopPlayback();try { player.play(audio,speed,normalizeVolume);playbackKey=key;playing=true;playbackPaused=false;main.post(playbackTicker) } catch(e:Exception) { error=e.message }
    }
    fun pausePlayback() {
        val file=filePlayer
        if(file!=null) { if(playbackPaused)file.start() else file.pause() } else { if(playbackPaused)player.resume() else player.pause() }
        playbackPaused=!playbackPaused
    }
    fun stopPlayback() { playbackEpoch.incrementAndGet();clearPlayback() }
    private fun clearPlayback() { main.removeCallbacks(playbackTicker);player.stop();filePlayer?.release();filePlayer=null;activePreview=null;playingFile=null;playbackKey=null;playing=false;playbackPaused=false }
    fun previewId(pack:OfflinePackage,language:String):String? {
        val id=if(pack.backend=="wayu")"wayu-$wayuVoice" else pack.id+if(pack.backend in setOf("supertonic","omnivoice"))"-$language" else ""
        return id.takeIf { "$it.m4a" in previews }
    }
    fun stopPreview() { if(activePreview!=null)stopPlayback() }
    fun stopHistoryPlayback() { if(filePlayer!=null && activePreview==null)stopPlayback() }
    fun playPreview(id:String) {
        if(activePreview==id) { stopPlayback();return };stopPlayback();activePreview=id
        try {
            val media=android.media.MediaPlayer();filePlayer=media
            getApplication<Application>().assets.openFd("VoicePreviews/$id.m4a").use { media.setDataSource(it.fileDescriptor,it.startOffset,it.length) }
            preparePlayer(media,id)
        } catch(e:Exception) { stopPlayback();error=e.message }
    }
    fun playHistory(name:String) {
        if(playingFile==name) { pausePlayback();return };val file=historyFile(name) ?: return;stopPlayback()
        try { val media=android.media.MediaPlayer();filePlayer=media;media.setDataSource(file.path);preparePlayer(media,name) }
        catch(e:Exception) { stopPlayback();error=e.message }
    }
    private fun preparePlayer(media:android.media.MediaPlayer,id:String) {
        media.setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH).build())
        media.setOnPreparedListener { if(filePlayer===it) { it.playbackParams=android.media.PlaybackParams().setSpeed(speed);it.start();playing=true;playbackPaused=false;playingFile=id } }
        media.setOnCompletionListener { if(filePlayer===it)stopPlayback() };media.setOnErrorListener { failed,_,_ -> if(filePlayer===failed) { stopPlayback();error=text("Не удалось воспроизвести файл.","Could not play the file.") };true };media.prepareAsync()
    }
    fun exportAudio(original:Boolean=false,ready:(File)->Unit) {
        val speech=if(original)originalAudio else translatedAudio[mode];if(speech==null || busy)return
        work(text("Подготовка аудио…","Preparing audio…")) {
            val file=File(exportDir,"${UUID.randomUUID()}.wav");player.exportWav(file,speech,normalizeVolume=original);checkCancelled();ui { if(!cancelled.get())ready(file) }
        }
    }
    private val ticker=object:Runnable { override fun run() {
        if(!recording)return
        val now=System.currentTimeMillis();val interval=if(lastRecordingTick==0L)0L else now-lastRecordingTick;lastRecordingTick=now
        recordingMillis=recorder.elapsedMillis;level=recorder.rms
        recorder.failure?.let { discardRecording();error=it;return }
        if(!recorder.isRecording) { finishRecording();return }
        if(!recordingPaused) { quietMillis=if(recorder.speechDetected)maxOf(0L,recordingMillis-recorder.lastSpeechMillis) else quietMillis+interval
            if((!activeRecordingHold && quietMillis>=activeRecordingSilence*1000L) || recordingMillis>=activeRecordingLimit*60_000L) { finishRecording();return } }
        if(!recordingPaused)offerRecordingPreview()
        main.postDelayed(this,100)
    } }
    fun beginRecording() {
        if(busy || recording || previewProcessing || !voiceReady)return
        try { cancelled.set(false);recordingPreview?.cancel();recordingPreview=null;previewMessage=null;stopPlayback();translatedAudio.remove("voice");audioRevision++;inputs["voice"]="";outputs["voice"]="";originalAudio=null
            error=null;quietMillis=0;lastRecordingTick=0;activeRecordingSilence=silenceSeconds;activeRecordingHold=recordingMode=="hold";activeRecordingLimit=recordingMinutes;activeRecordingSource=currentSource;activeRecordingTarget=target;activeRecordingSpeak=automaticSpeech
            recorder.start();recording=true;recordingPaused=false;recordingMillis=0
            if(recordingPreprocessing) {
                val thermal=getApplication<Application>().getSystemService(android.os.PowerManager::class.java).currentThermalStatus
                // Russian phrases are recognized live by GigaAM when installed (owner's decision 21.10); Whisper is
                // too slow on the Pixel to follow speech. Other languages keep the selected recognizer.
                val live=liveRecognition(currentSource)
                val backend=if(live!=null)"gigaam" else if(useSystemRecognition())null else runCatching { installedPackage(PackageCategory.RECOGNITION,currentSource,selectedRecognition()).first.backend }.getOrNull()
                val compatible=backend in setOf("whisper","gigaam")
                if(indexModel && installed && !memorySaving && compatible && thermal<android.os.PowerManager.THERMAL_STATUS_SEVERE) {
                    recordingPreview=RecordingPreview(currentSource,target,recordingVerification,automaticSpeech,punctuated=backend!="gigaam",recognizer=live)
                    previewMessage=text("Законченные фразы обрабатываются заранее. Озвучка — после остановки.","Completed phrases are processed now. Speech starts after recording stops.")
                } else previewMessage=text("Предварительная обработка недоступна для текущих моделей, настроек памяти или температуры. Перевод начнётся после остановки.","Preview is unavailable with these models, memory settings or temperature. Translation starts after recording stops.")
            }
            main.post(ticker)
        } catch(e:Exception) { error=e.message }
    }
    fun pauseRecording() { if(!recording)return;if(recordingPaused)recorder.resume() else recorder.pause();recordingPaused=!recordingPaused;lastRecordingTick=0 }
    private fun offerRecordingPreview() {
        val session=recordingPreview ?: return
        if(previewProcessing)return
        if(session.cancelled || session.suspended)return
        val thermal=getApplication<Application>().getSystemService(android.os.PowerManager::class.java).currentThermalStatus
        if(thermal>=android.os.PowerManager.THERMAL_STATUS_SEVERE) { session.suspend();previewMessage=text("Предварительная обработка приостановлена: устройство нагрелось.","Preview paused because the device is warm.");return }
        val range=session.next((recordingMillis*16).toInt(),(recorder.lastSpeechMillis*16).toInt())
        if(range==null) {
            if(session.suspended)previewMessage=text("Длинная незаконченная фраза будет обработана после остановки.","The long unfinished phrase will be processed after recording stops.")
            return
        }
        val samples=try { recorder.snapshot(range.first,range.last+1) } catch(_:Exception) { session.suspend();return }
        previewProcessing=true
        worker.execute {
            try {
                checkCancelled();if(session.cancelled || session.suspended)return@execute
                if(memorySaving)releaseTranslation()
                val recognized=transcribe(samples,session.prepared().language ?: session.source,session.recognizer)
                checkCancelled();if(session.cancelled || session.suspended || !session.accepts(recognized.text))return@execute
                val phrase=if(session.punctuated)recognized.text else RecordingPreview.sentence(recognized.text)
                val earlier=session.prepared()
                ui { if(recordingPreview===session && !session.cancelled)inputs["voice"]=listOf(earlier.sourceText,phrase).filter { it.isNotBlank() }.joinToString(" ") }
                // The phrase translation grows after the already committed ones, as in the text workspace.
                val stream:(String)->Unit={ partial -> ui { if(recordingPreview===session && !session.cancelled)outputs["voice"]=listOf(earlier.translation,partial).filter { it.isNotBlank() }.joinToString(" ") } }
                val translated=if(recognized.language==session.target)phrase else translateParts(phrase,session.target,recognized.language,stream)
                checkCancelled()
                if(session.commit(range,phrase,translated,recognized.language)) {
                    val result=session.prepared()
                    ui { if(recordingPreview===session && !session.cancelled) { inputs["voice"]=result.sourceText;outputs["voice"]=result.translation;detectedSource=result.language } }
                } else ui { if(recordingPreview===session && !session.cancelled) { val kept=session.prepared();inputs["voice"]=kept.sourceText;outputs["voice"]=kept.translation } }
            } catch(_:Exception) {
                session.suspend()
                ui { if(recordingPreview===session && !session.cancelled) { val kept=session.prepared();inputs["voice"]=kept.sourceText;outputs["voice"]=kept.translation } }
                ui { if(recordingPreview===session && !session.cancelled)previewMessage=text("Предварительная обработка остановлена. Полная запись будет обработана после остановки.","Preview stopped. The full recording will be processed after you stop.") }
            } finally { session.finishAttempt();ui { previewProcessing=false } }
        }
    }
    fun discardRecording() {
        main.removeCallbacks(ticker);recordingPreview?.cancel();recordingPreview=null;cancelled.set(true)
        systemSpeech.cancel();mlKitOcr.cancel();engine?.cancel();media.cancel();recorder.stop();recording=false;recordingPaused=false;recordingMillis=0;previewMessage=null
        inputs["voice"]="";outputs["voice"]=""
    }
    fun finishRecording() {
        if(!recording)return
        main.removeCallbacks(ticker)
        val speechEnd=(recorder.lastSpeechMillis*16).toInt()
        val samples=recorder.stop();recording=false;recordingPaused=false
        val session=recordingPreview
        if(samples.size<4000) { session?.cancel();recordingPreview=null;error=text("Запись слишком короткая. Попробуйте ещё раз.","Recording is too short. Try again.");return }
        originalAudio=SpeechAudio(samples,16000);audioRevision++
        val from=activeRecordingSource;val language=activeRecordingTarget;val speak=session?.speak ?: activeRecordingSpeak
        // Same serial worker joins the in-flight preview before reading its committed ledger.
        work(text("Распознаю речь…","Recognizing speech…"),"voice") {
            try {
                if(memorySaving)releaseTranslation()
                val prepared=session?.prepared()
                if(session!=null && !session.verify && prepared!=null && prepared.end>0) {
                    val tail=if(speechEnd<=prepared.end)FloatArray(0) else samples.copyOfRange(prepared.end.coerceAtMost(samples.size),samples.size)
                    val recognized=(if(tail.size>=4000)transcribe(tail,prepared.language ?: from,session.recognizer) else null)
                        ?.let { if(session.punctuated || it.text.isBlank()) it else it.copy(text=RecordingPreview.sentence(it.text)) }
                    checkCancelled()
                    val original=listOf(prepared.sourceText,recognized?.text.orEmpty()).filter { it.isNotBlank() }.joinToString(" ")
                    if(recognized!=null && recognized.text.isNotBlank())ui { inputs["voice"]=original }
                    val tailStream:(String)->Unit={ partial -> ui { if(!cancelled.get()) { outputs["voice"]=listOf(prepared.translation,partial).filter { it.isNotBlank() }.joinToString(" ");streamingOutput=true } } }
                    val tailTranslation=recognized?.text?.takeIf { it.isNotBlank() }?.let { if(recognized.language==language) it else translateParts(it,language,recognized.language,tailStream) }.orEmpty()
                    val translated=listOf(prepared.translation,tailTranslation).filter { it.isNotBlank() }.joinToString(" ")
                    finishTranslation(original,prepared.language ?: from,language,"voice",translated,speak)
                } else {
                    // Verification uses the complete recording and replaces provisional text.
                    // Re-translation is deliberate; no stale neighboring phrase is reused.
                    val transcript=transcribe(samples,from);checkCancelled()
                    check(transcript.text.isNotBlank()) { text("Речь не распознана.","No speech recognized.") }
                    ui { detectedSource=transcript.language;inputs["voice"]=transcript.text }
                    finishTranslation(transcript.text,transcript.language,language,"voice",speak=speak)
                }
            } catch(e:Exception) {
                if(!cancelled.get() && recordAudio)archive("","",from,language,"voice",null)
                throw e
            } finally { ui { if(recordingPreview===session) { recordingPreview=null;previewMessage=null } } }
        }
    }
    fun importAudio(uri:Uri) {
        if(busy || recording)return
        stopPlayback();originalAudio=null;inputs["voice"]="";outputs["voice"]="";translatedAudio.remove("voice");audioRevision++
        val from=currentSource;val language=target
        work(text("Чтение аудиофайла…","Reading audio file…"),"voice") {
            val samples=AudioImport.decode(getApplication(),uri) { cancelled.get() }
            checkCancelled();if(memorySaving)releaseTranslation()
            val recording=SpeechAudio(samples,16000)
            ui { originalAudio=recording;audioRevision++ }
            try {
                val transcript=transcribe(samples,from);checkCancelled();ui { inputs["voice"]=transcript.text;detectedSource=transcript.language }
                finishTranslation(transcript.text,transcript.language,language,"voice")
            } catch(e:Exception) {
                if(!cancelled.get() && recordAudio)archiveManualSpeech("",from,"voice",true,SpeechLoudness.normalizeRecording(recording))
                throw e
            }
        }
    }
    /** GigaAM spells numbers out; dates and clock times become digits, as Whisper writes them, before translation. */
    private fun spokenNumbers(text:String,language:String)=if(language=="ru")RussianSpokenNumbers.normalize(text) else text
    private fun liveRecognition(from:String):String?=if(from=="ru" && recognitionPreference=="automatic")packages.catalog.firstOrNull { it.category==PackageCategory.RECOGNITION && it.backend=="gigaam" && it.unavailableReason==null && packages.installedPath(it.id)!=null }?.id else null
    private fun automaticRecognition(from:String)=if(recognitionPreference=="automatic" && selectedRecognition()==null)
        RecognitionRouting.recommended(packages.catalog,from)?.id else null
    val automaticRecognitionPackage get()=automaticRecognition(currentSource)?.let { id -> packages.catalog.first { it.id==id } }
    private fun useSystemRecognition()=recognitionPreference=="system" ||
        (recognitionPreference=="automatic" && selectedRecognition()==null && systemRecognitionAvailable)
    private fun prepareRecognition(from:String) {
        val automatic=automaticRecognition(from)
        if(automatic==null && useSystemRecognition()) {
            media.releaseRecognition()
            systemSpeech.prepare(from) { cancelled.get() || closed.get() }
            return
        }
        systemSpeech.releasePrepared()
        val (pack,path)=installedPackage(PackageCategory.RECOGNITION,from,selectedRecognition() ?: automatic)
        packages.acquire(pack.id).use {
            checkCancelled()
            when(pack.backend) {
                "gigaam","parakeet" -> media.preloadNemo(path.path,pack.backend=="parakeet") { cancelled.get() || closed.get() }
                "omnilingual" -> media.preloadOmnilingual(findFile(path) { it.extension=="onnx" }.path,findFile(path) { it.name=="tokens.txt" }.path) { cancelled.get() || closed.get() }
                "whisper" -> media.preloadWhisper((if(path.isFile)path else findFile(path) { it.extension=="bin" }).path) { cancelled.get() || closed.get() }
                else -> error("Unsupported recognition backend")
            }
        }
    }
    /** [packageId] forces one installed recognizer (Russian live phrases use GigaAM); otherwise the user's choice applies. */
    private fun transcribe(samples:FloatArray,from:String,packageId:String?=null):Transcript = measure(ProcessingStage.RECOGNITION) {
        try { transcribeImpl(samples,from,packageId) } finally { if(!retainMediaModels() || (automaticRecognition(from)==null && useSystemRecognition()))releaseRecognition() }
    }
    private fun transcribeImpl(samples:FloatArray,from:String,packageId:String?=null):Transcript {
        checkCancelled();ui { status=text("Распознаю речь…","Recognizing speech…") }
        val automatic=automaticRecognition(from)
        if(packageId==null && automatic==null && useSystemRecognition()) {
            ui { recognitionBackend="android";status=text("Распознаю речь на устройстве…","Recognizing speech on device…") }
            try { return systemSpeech.transcribe(samples,from) { cancelled.get() || closed.get() } }
            catch(e:java.util.concurrent.CancellationException) { throw e }
            catch(e:Exception) {
                checkCancelled()
                throw IllegalStateException(text("Встроенное офлайн-распознавание недоступно для этой записи. Проверьте исходный язык и его пакет в настройках Android или выберите Whisper в настройках приложения.",
                    "On-device recognition is unavailable for this recording. Check the source language and its offline pack in Android settings, or choose Whisper in app settings."),e)
            }
        }
        if(automatic!=null && packages.installedPath(automatic)==null) {
            val title=packages.catalog.first { it.id==automatic }.title
            error(text("Модель распознавания %@ не скачана. Нажмите «Скачать распознавание».", "The %@ recognition model is not downloaded. Tap Download recognition.", (title)))
        }
        val (pack,path)=installedPackage(PackageCategory.RECOGNITION,from,packageId ?: selectedRecognition() ?: automatic)
        ui { recognitionBackend=pack.backend }
        return packages.acquire(pack.id).use {
            checkCancelled()
            if(pack.backend in setOf("gigaam","parakeet")) {
                val vad=File(getApplication<Application>().noBackupFilesDir,"silero_vad.onnx")
                if(!vad.isFile)getApplication<Application>().assets.open("silero_vad.onnx").use { input -> vad.outputStream().use { input.copyTo(it) } }
                try {
                    if(pack.backend=="parakeet")media.transcribeParakeet(path.path,samples,vad.path,from) { cancelled.get() || closed.get() }
                    else media.transcribeGigaAM(path.path,samples,vad.path) { cancelled.get() || closed.get() }.let { it.copy(text=spokenNumbers(it.text,it.language)) }
                }
                finally { if(!retainMediaModels())releaseRecognition() }
            } else if(pack.backend=="omnilingual") {
                val model=findFile(path) { it.extension=="onnx" };val tokens=findFile(path) { it.name=="tokens.txt" }
                media.transcribeOmnilingual(model.path,tokens.path,samples,from) { cancelled.get() || closed.get() }
            } else { val model=if(path.isFile)path else findFile(path) { it.extension=="bin" };media.transcribe(model.path,samples,pack.runtimeLanguage(from),whisperDateTimeRepair) { cancelled.get() || closed.get() } }
        }
    }
    private val cameraEpoch=java.util.concurrent.atomic.AtomicLong(0)
    @Volatile private var latestCameraSignature:IntArray?=null
    private var cameraAnchor:IntArray?=null
    var liveCameraProcessing by mutableStateOf(false);private set
    var liveCameraOverlay by mutableStateOf<Bitmap?>(null);private set
    var liveCameraMessage by mutableStateOf<String?>(null);private set
    private val cameraTranslations=linkedMapOf<String,String>() // worker-owned, bounded
    private fun cameraSignature(bitmap:Bitmap)=IntArray(24*24) { index ->
        val c=bitmap.getPixel((index%24*bitmap.width/24).coerceAtMost(bitmap.width-1),(index/24*bitmap.height/24).coerceAtMost(bitmap.height-1))
        (android.graphics.Color.red(c)*77+android.graphics.Color.green(c)*150+android.graphics.Color.blue(c)*29)/256
    }
    private fun cameraDistance(a:IntArray,b:IntArray)=a.indices.sumOf { kotlin.math.abs(a[it]-b[it]) }.toFloat()/(255*a.size)
    fun stopLiveCamera() {
        cameraEpoch.incrementAndGet();liveCameraOverlay=null;cameraAnchor=null;latestCameraSignature=null
        if(liveCameraProcessing) { mlKitOcr.cancel();engine?.cancel();media.cancel() }
    }
    fun receiveCameraFrame(frame:org.openoffline.translator.android.camera.CameraFrame,isCurrent:()->Boolean) {
        if(closed.get() || mode!="camera" || image!=null || busy || recording || !isCurrent()) { frame.close();return }
        val signature=cameraSignature(frame.bitmap);latestCameraSignature=signature
        if(cameraAnchor?.let { cameraDistance(it,signature)>.025f }==true) {
            cameraEpoch.incrementAndGet();liveCameraOverlay=null;cameraAnchor=signature
            if(liveCameraProcessing) { mlKitOcr.cancel();engine?.cancel();media.cancel() }
        }
        if(liveCameraProcessing) { frame.close();return }
        cameraAnchor=signature;val epoch=cameraEpoch.get();val from=cameraSource;val language=target
        liveCameraProcessing=true;liveCameraMessage=text("Распознаю текст…","Recognizing text…");cancelled.set(false)
        worker.execute {
            try {
                if(epoch!=cameraEpoch.get() || !isCurrent())return@execute
                checkCancelled();if(memorySaving)releaseTranslation()
                val width=frame.bitmap.width;val height=frame.bitmap.height
                val blocks=try { recognizeBlocks(frame.bitmap,from) { epoch!=cameraEpoch.get() || !isCurrent() || closed.get() || cancelled.get() } } finally { frame.close() }
                fun current()=epoch==cameraEpoch.get() && isCurrent() && !closed.get() && !cancelled.get()
                if(!current())return@execute
                if(blocks.isEmpty()) { ui { if(current()) { liveCameraOverlay=null;liveCameraMessage=text("Наведите камеру на текст","Point the camera at text") } };return@execute }
                ui { if(current())liveCameraMessage=text("Перевожу надписи…","Translating text…") }
                val translated=blocks.map { block ->
                    check(current())
                    val resolved=if(from=="auto")detectLanguage(block.text) ?: from else from
                    val key="$resolved|$language|${block.text}"
                    cameraTranslations[key] ?: translateParts(block.text,language,resolved).also {
                        cameraTranslations[key]=it
                        if(cameraTranslations.size>128)cameraTranslations.remove(cameraTranslations.keys.first())
                    }
                }
                check(current())
                val transparent=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888)
                val overlay=renderImage(transparent,blocks,translated);transparent.recycle()
                ui {
                    val latest=latestCameraSignature
                    if(current() && latest!=null && cameraDistance(signature,latest)<=.025f) {
                        liveCameraOverlay=overlay;liveCameraMessage=text("Перевод обновляется при изменении текста","Translation updates when text changes")
                    } else overlay.recycle()
                }
            } catch(e:Exception) {
                ui { if(epoch==cameraEpoch.get() && isCurrent())liveCameraMessage=e.message ?: text("Не удалось распознать текст.","Text recognition failed.") }
            } finally { frame.close();if(memorySaving)releaseTranslation();ui { liveCameraProcessing=false } }
        }
    }
    fun acceptCameraPhoto(bitmap:Bitmap) {
        stopLiveCamera();cameraNotice=null;image=bitmap;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]=""
        recognizeImage()
    }
    fun resumeCamera() { stopLiveCamera();cameraNotice=null;image=null;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]="";error=null }
    fun rectifyImage(corners:FloatArray) {
        val original=image ?: return
        work(text("Исправляю перспективу…","Correcting perspective…")) {
            val rectified=org.openoffline.translator.android.camera.ImagePerspective.rectify(original,corners)
            checkCancelled();ui { image=rectified;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]="" }
        }
    }
    private fun recognizeBlocks(bitmap:Bitmap,from:String,isCancelled:()->Boolean={cancelled.get() || closed.get()}):List<OcrBlock> {
        check(from!="auto") { text("Выберите язык текста на изображении.","Select the language of the image text.") }
        val script=OcrRouting.mlKitScript(from)
        ui { cameraNotice=if(script!=null)text("OCR: Google ML Kit · на устройстве", "OCR: Google ML Kit · on device") else text("OCR: PP-OCR · на устройстве", "OCR: PP-OCR · on device") }
        return if(script!=null)mlKitOcr.recognize(bitmap,script,isCancelled) else recognizeOpenBlocks(bitmap,from)
    }
    private fun recognizeOpenBlocks(bitmap:Bitmap,from:String):List<OcrBlock> {
        val detectorId=if(packages.installedPath("ppocr-v5-mobile-det")!=null)"ppocr-v5-mobile-det" else "ppocr-v5-det"
        val detector=packages.installedPath(detectorId) ?: error(text("Установите модель поиска текста OCR в разделе «Модели».","Install the OCR text detector in Models."))
        val choices=listOf(installedPackage(PackageCategory.OCR,from).first)
        check(choices.isNotEmpty()) { text("Установите OCR-пакет в разделе «Модели».","Install an OCR package in Models.") }
        val leases=mutableListOf<AutoCloseable>()
        try {
            leases+=packages.acquire(detectorId)
            val recognizers=choices.map { pack ->
                leases+=packages.acquire(pack.id)
                val path=packages.installedPath(pack.id) ?: error(text("OCR-пакет недоступен.","OCR package unavailable."))
                val dictionaryName=if(pack.id.contains("eslav"))"ocr-eslav-characters.json" else "ocr-english-characters.json"
                val chars=JSONArray(getApplication<Application>().assets.open(dictionaryName).bufferedReader().use { it.readText() })
                org.openoffline.translator.inference.OcrRecognizer(pack.id,path.path,(0 until chars.length()).map { chars.getString(it) })
            }
            val one=recognizers.single()
            return media.recognize(bitmap,detector.path,one.path,one.dictionary)
        } finally { leases.asReversed().forEach { it.close() } }
    }
    fun loadImage(uri:Uri) {
        stopLiveCamera()
        work(text("Открываю изображение…","Opening image…"),"camera") {
            val bitmap=ImageDecoder.decodeBitmap(ImageDecoder.createSource(getApplication<Application>().contentResolver,uri)) { decoder,info,_ ->
                decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE;val scale=minOf(1f,2048f/maxOf(info.size.width,info.size.height));decoder.setTargetSize((info.size.width*scale).toInt().coerceAtLeast(1),(info.size.height*scale).toInt().coerceAtLeast(1)) }
            checkCancelled();ui { cameraNotice=null;image=bitmap;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]="" }
            processPhoto(bitmap,cameraSource,target)
        }
    }
    fun cropImage(left:Float,top:Float,right:Float,bottom:Float) {
        val current=image ?: return
        val x=(left.coerceIn(0f,.95f)*current.width).toInt();val y=(top.coerceIn(0f,.95f)*current.height).toInt()
        val w=((right.coerceIn(left+.01f,1f)*current.width).toInt()-x).coerceIn(1,current.width-x)
        val h=((bottom.coerceIn(top+.01f,1f)*current.height).toInt()-y).coerceIn(1,current.height-y)
        image=Bitmap.createBitmap(current,x,y,w,h);ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]=""
    }
    fun recognizeImage() {
        cameraNotice=null
        val bitmap=image ?: return;val from=cameraSource;val language=target
        work(text("Распознаю текст…","Recognizing text…"),"camera") { processPhoto(bitmap,from,language) }
    }
    private fun processPhoto(bitmap:Bitmap,from:String,language:String) {
            if(memorySaving)releaseTranslation()
            val blocks=measure(ProcessingStage.RECOGNITION) { recognizeBlocks(bitmap,from) };checkCancelled()
            check(blocks.isNotEmpty()) { text("Текст не найден. Измените область или язык.","No text found. Change the crop or source language.") }
            ui { ocrBlocks=blocks;inputs["camera"]=blocks.joinToString("\n") { it.text } }
            val translated=blocks.map { checkCancelled();translateParts(it.text,language,if(from=="auto")detectLanguage(it.text) ?: from else from) };checkCancelled()
            val original=blocks.joinToString("\n") { it.text };val result=translated.joinToString("\n")
            ui { translatedBlocks=translated;outputs["camera"]=result }
            archive(original,result,from,language,"camera",null,renderImage(bitmap,blocks,translated))
    }
    fun rotateImage() {
        val original=image ?: return;val transform=android.graphics.Matrix().apply { postRotate(90f) }
        image=Bitmap.createBitmap(original,0,0,original.width,original.height,transform,true);ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]=""
    }
    fun exportPicture(ready:(File)->Unit) {
        val bitmap=image ?: return;val blocks=ocrBlocks;val texts=translatedBlocks
        work(text("Подготовка изображения…","Preparing image…")) {
            val rendered=renderImage(bitmap,blocks,texts);val file=File(exportDir,"${UUID.randomUUID()}.png")
            file.outputStream().use { out -> check(rendered.compress(Bitmap.CompressFormat.PNG,100,out)) };checkCancelled();ui { if(!cancelled.get())ready(file) }
        }
    }
    fun saveCameraToGallery() {
        val bitmap=image ?: return;val blocks=ocrBlocks;val texts=translatedBlocks
        cameraNotice=null
        work(text("Сохранение…","Saving…")) {
            val rendered=renderImage(bitmap,blocks,texts)
            val resolver=getApplication<Application>().contentResolver
            val values=android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,"Kat-${System.currentTimeMillis()}.png")
                put(android.provider.MediaStore.Images.Media.MIME_TYPE,"image/png")
                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,"Pictures/Kat translator")
                put(android.provider.MediaStore.Images.Media.IS_PENDING,1)
            }
            val uri=resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values) ?: error(text("Не удалось сохранить изображение.","Could not save image."))
            try {
                resolver.openOutputStream(uri,"w")!!.use { output -> check(rendered.compress(Bitmap.CompressFormat.PNG,100,output)) }
                checkCancelled();values.clear();values.put(android.provider.MediaStore.Images.Media.IS_PENDING,0);resolver.update(uri,values,null,null)
                ui { cameraNotice=text("Изображение сохранено в галерею","Image saved to gallery");status=cameraNotice!! }
            } catch(e:Exception) { resolver.delete(uri,null,null);throw e }
            finally { rendered.recycle() }
        }
    }
    fun clearCameraText() { stopLiveCamera();cameraNotice=null;ocrBlocks=emptyList();translatedBlocks=emptyList();inputs["camera"]="";outputs["camera"]="" }
    fun saveExport(file:File,uri:Uri) {
        work(text("Сохранение…","Saving…")) { getApplication<Application>().contentResolver.openOutputStream(uri,"wt")!!.use { out -> file.inputStream().use { it.copyTo(out) } };ui { status=text("Сохранено","Saved") } }
    }
    fun exportImage():File? { val bitmap=image ?: return null;val rendered=renderImage(bitmap,ocrBlocks,translatedBlocks);return File(exportDir,"translation.png").also { it.outputStream().use { out -> rendered.compress(Bitmap.CompressFormat.PNG,100,out) } } }
    private fun renderImage(bitmap:Bitmap,blocks:List<OcrBlock>,translations:List<String>):Bitmap {
        val rendered=bitmap.copy(Bitmap.Config.ARGB_8888,true);val canvas=android.graphics.Canvas(rendered);val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        blocks.zip(translations).forEach { (block,text) ->
            val left=block.left*bitmap.width;val top=block.top*bitmap.height;val width=((block.right-block.left)*bitmap.width).toInt().coerceAtLeast(40)
            val textPaint=android.text.TextPaint(paint).apply { color=android.graphics.Color.BLACK;textSize=maxOf(12f,(block.bottom-block.top)*bitmap.height*.7f) }
            val layout=android.text.StaticLayout.Builder.obtain(text,0,text.length,textPaint,width).build()
            paint.color=android.graphics.Color.WHITE;canvas.drawRect(left,top,left+width,top+maxOf(layout.height.toFloat(),(block.bottom-block.top)*bitmap.height),paint)
            canvas.save();canvas.translate(left,top);layout.draw(canvas);canvas.restore()
        };return rendered
    }
    private fun archiveManualSpeech(content:String,language:String,workspace:String,original:Boolean,speech:SpeechAudio) {
        if(!recordAudio)return
        if(!original)historyTargets[workspace]?.let { (id,text,target) ->
            if(content==text && language==target && history.any { it.id==id } && appendHistorySpeech(id,speech))return
        }
        val id=UUID.randomUUID().toString();val file=File(archiveDir,"$id.wav")
        player.exportWav(file,speech);checkCancelled()
        val entry=TranslationEntry(id,if(original && recordHistory)content else "",if(!original && recordHistory)content else "",language,System.currentTimeMillis(),language,workspace,if(original)null else file.name,null,if(original)file.name else null)
        ui { if(!cancelled.get()) { history=listOf(entry)+history;pruneHistory();saveHistory() } else deleteFiles(entry) }
    }
    private fun appendHistorySpeech(id:String,speech:SpeechAudio):Boolean {
        if(!recordAudio)return false
        val file=File(archiveDir,"$id.wav");val temporary=File(archiveDir,"$id.partial.wav")
        try { player.exportWav(temporary,speech);checkCancelled();check(temporary.renameTo(file)) { "Could not save audio" } }
        finally { temporary.delete() }
        ui {
            if(history.any { it.id==id }) { history=history.map { if(it.id==id)it.copy(audio=file.name) else it };pruneHistory();saveHistory() }
            else file.delete()
        }
        return true
    }
    private fun archive(original:String,translated:String,from:String,target:String,kind:String,speech:SpeechAudio?,picture:Bitmap?=null):String? {
        if(!recordHistory && !(recordAudio && (speech!=null || (kind=="voice" && originalAudio!=null))) && !(recordImages && picture!=null))return null
        checkCancelled()
        val id=UUID.randomUUID().toString();var audioPath:String?=null;var imagePath:String?=null;var originalPath:String?=null
        if(recordAudio && speech!=null) { val file=File(archiveDir,"$id.wav");player.exportWav(file,speech);audioPath=file.name }
        if(recordAudio && kind=="voice" && originalAudio!=null) { val file=File(archiveDir,"$id-original.wav");player.exportWav(file,originalAudio!!,normalizeVolume=true);originalPath=file.name }
        if(recordImages && picture!=null) { val file=File(archiveDir,"$id.png");file.outputStream().use { picture.compress(Bitmap.CompressFormat.PNG,100,it) };imagePath=file.name }
        val entry=TranslationEntry(id,if(recordHistory)original else "",if(recordHistory)translated else "",target,System.currentTimeMillis(),from,kind,audioPath,imagePath,originalPath)
        if(cancelled.get()) { deleteFiles(entry);checkCancelled() }
        // This result is complete. A later cancellation of TTS must not discard it.
        ui { history=listOf(entry)+history;pruneHistory();saveHistory() }
        if(translated.isNotBlank())historyTargets[kind]=Triple(id,translated,target)
        return id
    }
    fun historyFile(name:String?):File?=name?.takeIf { it==File(it).name }?.let { File(archiveDir,it) }?.takeIf { it.isFile }
    fun openHistory(entry:TranslationEntry) {
        if(busy || recording)return
        mode=if(entry.kind=="camera")"text" else entry.kind;input=entry.original;output=entry.translated;target=entry.target;source=entry.source;saveLanguages()
        if(mode=="voice") {
            originalAudio=null;audioRevision++
            historyFile(entry.originalAudio)?.let { file -> work(text("Открываю запись…","Opening recording…")) {
                val samples=AudioImport.decode(getApplication(),Uri.fromFile(file)) { cancelled.get() || closed.get() }
                checkCancelled();ui { originalAudio=SpeechAudio(samples,16000);audioRevision++ }
            } }
        }
    }
    fun deleteHistory(id:String) { if(history.any { it.id==id && playingFile in listOfNotNull(it.audio,it.originalAudio) })stopPlayback();history.filter { it.id==id }.forEach(::deleteFiles);history=history.filterNot { it.id==id };saveHistory() }
    fun clearHistory() { stopHistoryPlayback();history.forEach(::deleteFiles);history=emptyList();saveHistory() }
    private fun deleteFiles(entry:TranslationEntry) { listOf(entry.audio,entry.image,entry.originalAudio).forEach { historyFile(it)?.delete() } }
    private fun restoreHistory() {
        try { val rows=JSONArray(prefs.getString("history","[]"));history=(0 until rows.length()).map { i -> rows.getJSONObject(i).let { TranslationEntry(it.getString("id"),it.optString("original"),it.optString("translated"),it.getString("target"),it.getLong("time"),it.optString("source","auto"),it.optString("kind","text"),it.optString("audio").ifEmpty { null },it.optString("image").ifEmpty { null },it.optString("originalAudio").ifEmpty { null }) } };pruneHistory() }
        catch(_:Exception) { error=text("Не удалось прочитать историю переводов","Could not read translation history") }
    }
    private fun pruneHistory() {
        var textCount=0;var pictures=0;val now=System.currentTimeMillis()
        val keptAudio=org.openoffline.translator.android.history.AudioHistoryRetention.select(history.map { org.openoffline.translator.android.history.AudioRetentionEntry(it.id,it.time,it.audio,it.originalAudio) },audioCount,audioDays,now)
        history=history.mapNotNull { original ->
            var row=original
            fun expired(days:Int)=days>0 && now-row.time>days*86_400_000L
            if(row.original.isNotEmpty() || row.translated.isNotEmpty()) { textCount++;if((historyCount>0 && textCount>historyCount) || expired(historyDays))row=row.copy(original="",translated="") }
            if(row.audio!=null && row.audio !in keptAudio) { historyFile(row.audio)?.delete();row=row.copy(audio=null) }
            if(row.originalAudio!=null && row.originalAudio !in keptAudio) { historyFile(row.originalAudio)?.delete();row=row.copy(originalAudio=null) }
            if(row.image!=null) { pictures++;if((imageCount>0 && pictures>imageCount) || expired(imageDays)) { historyFile(row.image)?.delete();row=row.copy(image=null) } }
            if(row.original.isEmpty() && row.translated.isEmpty() && row.audio==null && row.image==null && row.originalAudio==null)null else row
        }
    }
    private fun saveHistory() { val rows=JSONArray();history.forEach { rows.put(JSONObject().put("id",it.id).put("original",it.original).put("translated",it.translated).put("target",it.target).put("time",it.time).put("source",it.source).put("kind",it.kind).put("audio",it.audio ?: "").put("image",it.image ?: "").put("originalAudio",it.originalAudio ?: "")) };prefs.edit().putString("history",rows.toString()).apply() }
    val translationRuntimeLabel get()=(if(translationModel==AUTO_TRANSLATION)"Авто · " else "")+when(effectiveModel) { "opus" -> "OPUS-MT · INT8 · CPU";"index2b" -> "Index-Translate 2B · Q4_K_M · Vulkan";else -> "Index-Translate 9B · Q4_K_M · Vulkan" }
    fun diagnostics():String {
        val info=ActivityManager.MemoryInfo();(getApplication<Application>().getSystemService(Application.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
        return "Kat translator Android\n${translationRuntimeLabel}\nMTP: $mtpActive\nPackage check: ${packages.restorationSeconds} s (${packages.startupCachedPackages} cached, ${packages.startupFullVerifications} full checks)\nPreparation: ${preparationSeconds ?: "—"} s\nWorkspace: $mode\nRecognition: ${timing?.recognition ?: "—"} s\nTranslation: ${seconds ?: "—"} s\nSpeech synthesis: ${timing?.synthesis ?: "—"} s\nModel load: ${timing?.modelLoad ?: "—"} s\nTotal processing (excludes recording/playback): ${timing?.total ?: "—"} s\nFirst token: ${firstToken ?: "—"} s\nRAM free: ${info.availMem/1024/1024} MiB / ${info.totalMem/1024/1024} MiB\nStorage free: ${archiveDir.usableSpace/1024/1024} MiB\nAndroid: ${android.os.Build.VERSION.RELEASE}\nDevice: ${android.os.Build.MODEL}"
    }
    fun background() {
        inForeground=false
        main.removeCallbacks(memoryTicker)
        stopLiveCamera()
        if(recording)discardRecording()
        recordingPreview?.suspend()
        if(previewProcessing) { engine?.cancel();media.cancel() }
        cancel();stopPlayback();trimMemory()
    }
    override fun onCleared() { closed.set(true);cancelled.set(true);systemSpeech.close();mlKitOcr.close();recordingPreview?.cancel();main.removeCallbacks(ticker);main.removeCallbacks(playbackTicker);main.removeCallbacks(memoryTicker);recorder.stop();player.stop();filePlayer?.release();engine?.cancel();opus?.cancel();media.cancel();worker.execute { releaseTranslation();media.close() };worker.shutdown();voiceLoader.shutdownNow() }
}
