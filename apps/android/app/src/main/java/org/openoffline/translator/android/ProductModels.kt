package org.openoffline.translator.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.openoffline.translator.android.packages.*
import org.openoffline.translator.inference.IndexLanguages
import org.openoffline.translator.inference.OfflineMedia

/** Sizes in the app language: «ГБ/МБ» with a decimal comma in Russian, «GB/MB» in English. */
@Composable private fun bytes(value:Long):String {
    val locale=java.util.Locale.forLanguageTag(LocalUiLanguage.current)
    return if(value>=1_000_000_000)String.format(locale,"%.2f\u00A0%s",value/1e9,tr("ГБ","GB")) else String.format(locale,"%.1f\u00A0%s",value/1e6,tr("МБ","MB"))
}
@Composable internal fun rememberPackageDownload(state:TranslatorState,afterStart:()->Unit={}):(List<String>)->Unit {
    val context=LocalContext.current
    val latestAfterStart by rememberUpdatedState(afterStart)
    val lifecycle=androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var pending by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var confirm by remember { mutableStateOf<List<String>>(emptyList()) }
    var allowCellular by remember { mutableStateOf(state.allowCellular) }
    var network by remember { mutableStateOf(DownloadAccess.networkState(context)) }
    LaunchedEffect(confirm) { while(confirm.isNotEmpty()) { network=DownloadAccess.networkState(context);kotlinx.coroutines.delay(500) } }
    fun visible()=lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        val ids=pending;pending=emptyList();if(ids.isNotEmpty())state.startPackages(ids,::visible) { latestAfterStart() }
    }
    fun start(ids:List<String>) {
        if(android.os.Build.VERSION.SDK_INT>=33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) { pending=ids;permission.launch(Manifest.permission.POST_NOTIFICATIONS) }
        else state.startPackages(ids,::visible) { latestAfterStart() }
    }
    if(confirm.isNotEmpty())AlertDialog(
        onDismissRequest={confirm=emptyList()},title={Text(if(network==DownloadNetworkState.OFFLINE || network==DownloadNetworkState.UNKNOWN)tr("Нет подключения к интернету") else tr("Загрузка без обычного Wi-Fi"))},
        text={Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(tr("Будет скачано до ","Download up to ")+bytes(state.packages.maximumDownloadBytes(confirm)),modifier=Modifier.testTag("download.confirm.bytes"))
            Note(if(network==DownloadNetworkState.OFFLINE || network==DownloadNetworkState.UNKNOWN)tr("Подключитесь к Wi-Fi или включите мобильный интернет. Одного разрешения в приложении недостаточно, если сети нет.") else tr("Подключение может использовать мобильный трафик. Чтобы скачать модели через него, разрешите мобильный интернет."))
            ToggleRow(tr("Разрешить мобильный интернет"),allowCellular,tag="download.confirm.cellular") { allowCellular=it }
            Note(tr("Установленные пакеты не скачиваются повторно. При продолжении прерванной загрузки может потребоваться скачать файл заново."))
        }},
        confirmButton={TextButton(onClick={val ids=confirm;confirm=emptyList();state.changeAllowCellular(allowCellular);start(ids)},enabled=network.canDownload(allowCellular),modifier=Modifier.testTag("download.confirm.start")) { Text(tr("Скачать")) }},
        dismissButton={TextButton(onClick={confirm=emptyList()}) { Text(tr("Отмена","Cancel")) }}
    )
    return { ids ->
        if(ids.isEmpty())latestAfterStart()
        else if(state.packages.maximumDownloadBytes(ids)>0 && DownloadAccess.networkState(context).requiresConfirmation) { network=DownloadAccess.networkState(context);allowCellular=state.allowCellular;confirm=ids } else start(ids)
    }
}
@Composable private fun rememberDownload(state:TranslatorState)=rememberPackageDownload(state)
@Composable internal fun ModelsSheet(state:TranslatorState,navigate:(String)->Unit) {
    val context=LocalContext.current
    val states by state.packages.states.collectAsState()
    val restored by state.packages.restored.collectAsState()
    val download=rememberDownload(state)
    val plan=state.setupPlan(state.languageSetup.withActivePair(state.source,state.target));val progress=plan.summary(states)
    val catalog=state.packages.catalog
    LazyColumn(Modifier.fillMaxSize().testTag("models.list"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item {
            Group("") {
                Text(tr("Модели выполняют перевод на Android. После скачивания сеть для перевода не нужна.","Models translate on Android. Translation needs no network after downloading."))
                TextButton(contentPadding=GroupActionPadding,onClick={navigate("setup")},modifier=Modifier.testTag("models.languageSetup")) { Text(tr("Настроить языки и загрузку")) }
                ToggleRow(tr("Разрешить мобильный интернет"),state.allowCellular,tag="models.allowCellular",action=state::changeAllowCellular)
                if(!restored)Text(tr("Проверяю модели…"))
                else if(progress.busy) {
                    CatProgress(progress.fraction)
                    TextButton(contentPadding=GroupActionPadding,onClick={state.packages.catalog.filter { states[it.id]?.busy==true }.forEach { state.packages.pause(it.id) }}) { Text(tr("Приостановить скачивание")) }
                } else if(!progress.ready)TextButton(contentPadding=GroupActionPadding,onClick={download(plan.ids)},enabled=plan.isValid,modifier=Modifier.testTag("models.downloadAll")) { Text(tr("Скачать модели · ")+bytes(progress.remainingBytes)) }
                else Status(tr("Пакеты для перевода готовы"))
                ErrorText(state)
            }
        }
        item {
            Group(tr("Модель перевода")) {
                Note(tr("Index 2B — 150 языков, быстрый. Index 9B — максимальное качество, медленнее. OPUS Big — компактные модели для отдельных направлений (русский ↔ европейские языки, английский ↔ ~30 языков); каждое направление скачивается отдельно.","Index 2B: 150 languages, fast. Index 9B: maximum quality, slower. OPUS Big: compact models for separate directions (Russian ↔ European languages, English ↔ ~30 languages); each direction downloads separately."))
                Column(Modifier.fillMaxWidth().clickable(enabled=restored && !state.busy) { state.selectTranslation(AUTO_TRANSLATION) }.testTag("model.select.auto")) {
                    Text(tr("Авто","Auto"),fontWeight=FontWeight.SemiBold)
                    Note(if(state.strongDevice)tr("Мощное устройство: Index 9B для всех языков.","Powerful device: Index 9B for all languages.")
                        else tr("Для каждой пары — установленная модель OPUS, иначе Index 2B или 9B.","Each pair uses an installed OPUS model, otherwise Index 2B or 9B."))
                    Status(tr("Рекомендуется","Recommended"))
                    if(state.translationModel==AUTO_TRANSLATION)Status(tr("Выбрана","Selected"))
                }
                // OPUS pair packages share one selectable OPUS entry; they are listed for download below.
                catalog.filter { it.category==PackageCategory.TRANSLATION && (it.backend!="opus" || it.id==PackageCatalog.DEFAULT_TRANSLATION_ID) }.sortedBy { when(it.backend) { "opus" -> 0;PackageCatalog.MULTILINGUAL_BACKEND -> 1;else -> 2 } }.forEach { pack ->
                    Row(verticalAlignment=Alignment.Top) {
                        Column(Modifier.weight(1f).clickable(enabled=pack.unavailableReason==null && restored && !state.busy) { state.selectTranslation(pack.backend) }.testTag("model.select.${pack.id}")) {
                            Text(tr(pack.title),fontWeight=FontWeight.SemiBold,modifier=Modifier.testTag(if(pack.backend in PackageCatalog.INDEX_MODELS)"model.${pack.backend}" else "model.${pack.id}"))
                            Note(bytes(pack.downloadBytes)+" · "+languageCount(pack.languages.size))
                            Note(when(pack.backend) { "opus" -> tr("Меньше расход памяти, чем у моделей 4B–9B");"index" -> tr("RAM телефона: от 12 ГБ (ориентир)");else -> tr("Меньше памяти, чем у 9B","Uses less memory than 9B") })
                            Note(when(pack.backend) { "opus" -> tr("Компактный офлайн-переводчик · меньше загрузка и расход памяти");"index" -> tr("150 языков · максимальное качество · требует больше памяти и времени","150 languages · maximum quality · uses more memory and time");else -> tr("150 языков · примерно в 3 раза быстрее 9B","150 languages · about 3× faster than 9B") })
                            if(state.translationModel==pack.backend)Status(tr("Выбрана","Selected"))
                            pack.unavailableReason?.let { Note(tr(it,pack.unavailableReasonEnglish)) }
                        }
                        TextButton(onClick={navigate("modelInfo:${pack.id}")},modifier=Modifier.testTag("model.info.${pack.id}")) { Text("ⓘ") }
                    }
                }
                Note(tr("Число языков заявлено авторами моделей. Озвучка и камера имеют отдельные ограничения.","Language coverage is reported by model authors. Speech and camera have separate limitations."))
                catalog.firstOrNull { it.backend==state.translationModel }?.sourceURL?.takeIf { it.isNotEmpty() }?.let { link -> TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(link)))}) { Text(tr("О модели и лицензии")) } }
                TextButton(contentPadding=GroupActionPadding,onClick=state::unload,enabled=state.modelReady && !state.busy,modifier=Modifier.testTag("model.unload")) { Text(tr("Выгрузить из памяти")) }
                Note(tr("Выбор другой модели освобождает память предыдущей. Скачанные файлы остаются на телефоне; удалить их можно отдельной кнопкой ниже."))
            }
        }
        item { Group(tr("Распознавание речи")) { Note(tr("Авто выбирает GigaAM для русского и Parakeet для остальных 24 поддерживаемых языков. Скачайте нужные пакеты один раз; затем распознавание работает без интернета.","Auto selects GigaAM for Russian and Parakeet for the other 24 supported languages. Download the required packages once; recognition then works offline."));Note(tr("Первая подготовка распознавания может занять несколько минут. При смене языка может понадобиться загрузка другого распознавания.")) } }
        items(catalog.filter { it.backend=="coreml" },key={it.id}) { PackagePanel(state,it,states[it.id],download) }
        item {
            val directions=catalog.filter { it.opusRoutes.isNotEmpty() && it.id!=PackageCatalog.DEFAULT_TRANSLATION_ID }
            Group(tr("OPUS · направления перевода","OPUS · translation directions")) {
                Note(tr("Установлено %@ из %@ направлений. Выберите нужные языки и скачайте их одной кнопкой.", "%@ of %@ directions installed. Choose languages and download them with one button.", (directions.count { states[it.id]?.phase==PackagePhase.INSTALLED }), (directions.size)))
                TextButton(contentPadding=GroupActionPadding,onClick={navigate("opusDirections")},modifier=Modifier.testTag("models.opusDirections")) { Text(tr("Выбрать направления","Choose directions")) }
            }
        }
        // Direction packages are managed in their own sheet; the English OPUS package stays here.
        items(listOf("opus","gigaam","parakeet","whisper","index2b","index").flatMap { backend -> catalog.filter { it.backend==backend && (backend!="opus" || it.id==PackageCatalog.DEFAULT_TRANSLATION_ID) } },key={it.id}) { PackagePanel(state,it,states[it.id],download) }
        item { Group(tr("Дополнительное распознавание")) { Note(tr("Meta Omnilingual добавляет голосовой ввод для дополнительных языков. Новые направления экспериментальные; язык выбирается вручную.","Meta Omnilingual adds voice input for additional languages. These directions are experimental; select the language manually.")) } }
        items(catalog.filter { it.backend=="omnilingual" },key={it.id}) { PackagePanel(state,it,states[it.id],download) }
        item { Group(tr("Офлайн и восстановление")) { Note(tr("Приостановленную загрузку можно продолжить, если сервер сохранил данные. Изменение мобильной сети применяется только к новой загрузке. Выбор, скачивание и удаление голосов доступны в настройках → Голоса и образцы.")) } }
    }
}
@Composable private fun PackagePanel(state:TranslatorState,pack:OfflinePackage,status:PackageStatus?,download:(List<String>)->Unit,voiceLanguage:String?=null) {
    val context=LocalContext.current
    val restored by state.packages.restored.collectAsState()
    val lifecycle=androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var remove by remember { mutableStateOf(false) }
    val importer=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if(uri!=null) {
            try { context.contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch(_:SecurityException) { }
            state.importPackage(pack.id,uri) { lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED) }
        }
    }
    Group(if(voiceLanguage==null)tr(pack.title) else "") {
        if(voiceLanguage!=null)Text(tr(pack.title),fontWeight=FontWeight.SemiBold)
        SettingRow(tr("Загрузка","Download"),bytes(pack.downloadBytes))
        if(voiceLanguage!=null) {
            if(pack.backend=="wayu")MenuSetting(tr("Голос Wayu"),state.wayuVoice,OfflineMedia.wayuVoices.map { it to it.replace('_',' ') },"voices.wayu.speaker",state::selectWayu)
            state.previewId(pack,voiceLanguage)?.let { id -> TextButton(onClick={state.playPreview(id)},modifier=Modifier.testTag("voices.preview.$voiceLanguage.${pack.id}")) { Text(if(state.playingFile==id)tr("Остановить образец") else tr("Послушать образец")) } }
            if(state.selectedVoice(voiceLanguage)==pack.id)Status(tr("Выбрано","Selected"))
        }
        if(pack.sourceURL.isNotEmpty())TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(pack.sourceURL)))}) { Text(when {
            voiceLanguage==null -> tr("О модели и лицензии")
            pack.backend=="wayu" -> "Wayu Kokoro · Apache 2.0"
            pack.backend=="supertonic" -> "Supertonic 3 · OpenRAIL-M"
            pack.id=="mms-tts-ban-onnx" -> "Meta MMS · CC BY-NC 4.0"
            pack.id=="vits-piper-zh_CN-huayan-medium" -> tr("Huayan · условия исходных данных не указаны")
            else -> tr("Источник и условия голоса")
        }) }
        if(pack.license.isNotEmpty())Note(pack.license)
        if(voiceLanguage!=null && pack.backend=="wayu")Note(tr("12 голосов в одном пакете. Для тайского текста; редкие английские имена могут не озвучиваться."))
        if(voiceLanguage!=null && pack.backend=="omnivoice")Note(tr("Общий пакет OmniVoice скачивается один раз. Требует больше памяти и времени, чем лёгкие голоса; качество зависит от языка. Даже короткая фраза может обрабатываться больше минуты.","The shared OmniVoice package downloads once. It uses more memory and time than lightweight voices; quality depends on the language. Even a short phrase may take more than a minute."))
        if(voiceLanguage=="ban") {
            TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://huggingface.co/willwade/mms-tts-multilingual-models-onnx")))}) { Text(tr("Преобразование в ONNX: Will Wade")) }
            Note(tr("Экспериментальный балийский голос для текста латиницей и некоммерческого использования. Произношение пока не проверено носителем языка."))
        } else if(voiceLanguage!=null && (pack.backend in setOf("mms","omnivoice") || (pack.backend=="piper" && pack.license.isNotEmpty())))Note(tr("Экспериментальный голос. Синтез проверен; произношение пока не проверено носителем языка."))
        if(pack.unavailableReason!=null)Note(tr(pack.unavailableReason,pack.unavailableReasonEnglish))
        else {
            if(status?.busy==true || status?.phase==PackagePhase.PAUSED)CatProgress(status.progress.takeIf { status.phase==PackagePhase.DOWNLOADING || status.phase==PackagePhase.PAUSED })
            status?.let {
                Text(if(it.phase==PackagePhase.INSTALLED)tr("Скачано и проверено") else phaseName(it.phase),color=if(it.phase==PackagePhase.INSTALLED)KatAccent else Muted,
                    modifier=if(it.phase==PackagePhase.INSTALLED)Modifier.testTag("model.installed.${pack.id}") else Modifier)
                if(it.busy || it.phase==PackagePhase.PAUSED)Note(bytes(it.downloadedBytes)+" / "+bytes(it.totalBytes))
            }
            PackageMessages.display(status?.message,state.uiLanguage)?.let { Note(it) }
            if(status?.phase==PackagePhase.INSTALLED) {
                if(pack.category==PackageCategory.RECOGNITION)TextButton(contentPadding=GroupActionPadding,onClick={state.selectRecognition(pack.id)},enabled=!state.busy && state.selectedRecognition()!=pack.id,modifier=Modifier.testTag("recognition.${pack.id}.select")) {
                    Text(if(state.selectedRecognition()==pack.id)tr("Выбрано","Selected") else tr("Использовать для распознавания","Use for recognition"))
                }
                if(voiceLanguage!=null)TextButton(contentPadding=GroupActionPadding,onClick={state.selectVoice(voiceLanguage,pack.id)},enabled=state.selectedVoice(voiceLanguage)!=pack.id,modifier=Modifier.testTag("voice.$voiceLanguage.${pack.id}.select")) { Text(tr("Использовать этот голос")) }
                TextButton(contentPadding=GroupActionPadding,onClick={remove=true},modifier=Modifier.testTag("models.remove.${pack.id}")) { Text(if(voiceLanguage!=null)tr("Удалить голос") else tr("Удалить"),color=Color(0xFFFF6961)) }
            } else if(status?.busy==true)TextButton(contentPadding=GroupActionPadding,onClick={state.packages.pause(pack.id)}) { Text(tr("Пауза")) }
            else TextButton(contentPadding=GroupActionPadding,onClick={download(listOf(pack.id))},enabled=restored && !state.busy,modifier=Modifier.testTag(if(voiceLanguage!=null)"voices.download.${pack.id}" else "models.download.${pack.id}")) { Text(if(status?.phase==PackagePhase.PAUSED)tr("Продолжить скачивание") else if(voiceLanguage!=null)tr("Скачать голос") else tr("Скачать")) }
            if(status?.busy==true || status?.phase==PackagePhase.PAUSED)TextButton(contentPadding=GroupActionPadding,onClick={state.packages.cancel(pack.id)}) { Text(tr("Отменить скачивание")) }
            if(status?.busy!=true && voiceLanguage==null)TextButton(contentPadding=GroupActionPadding,onClick={importer.launch(arrayOf("*/*"))},modifier=Modifier.testTag(if(pack.backend=="index")"models.import" else "models.import.${pack.id}")) { Text(tr("Импорт","Import")) }
        }
    }
    if(remove)AlertDialog(onDismissRequest={remove=false},title={Text(if(voiceLanguage!=null)tr("Удалить голос?") else tr("Удалить пакет?"))},text={Text(if(voiceLanguage!=null)
        (if(pack.languages.size>1)tr("Общий пакет удалится для всех использующих его языков. ") else "")+tr("Голос можно скачать снова. После удаления выбранного голоса озвучка будет недоступна, пока вы не скачаете его или не выберете другой.")
        else tr("Перед удалением активная обработка остановится. Пакет можно скачать снова."))},confirmButton={TextButton(onClick={state.removePackage(pack.id);remove=false}) { Text(tr("Удалить")) }},dismissButton={TextButton(onClick={remove=false}) { Text(tr("Отмена","Cancel")) }})
}
@Composable internal fun VoiceSettingsSheet(state:TranslatorState,initialLanguage:String?=null) {
    DisposableEffect(state) { onDispose { state.stopPreview() } }
    val states by state.packages.states.collectAsState();val restored by state.packages.restored.collectAsState()
    val download=rememberDownload(state);val plan=state.voiceDownloadPlan();val progress=plan.summary(states)
    val voices=state.packages.catalog.filter { it.category==PackageCategory.VOICE }
    // Voice coverage is independent of translation; Balinese remains a standalone voice.
    val languages=(IndexLanguages.all.map { it.id }+voices.flatMap { it.languages }).distinct().filter { language -> voices.any { it.supports(language) } }
    val scroll=rememberLazyListState()
    LaunchedEffect(initialLanguage,languages) { languages.indexOfFirst { it==initialLanguage }.takeIf { it>=0 }?.let { scroll.scrollToItem(it+1) } }
    LazyColumn(Modifier.fillMaxSize().testTag("voices.list"),state=scroll,contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item { Group(tr("Все языки")) {
            val ready=languages.count { lang -> val selected=voices.firstOrNull { it.id==state.selectedVoice(lang) && it.supports(lang) } ?: voices.first { it.supports(lang) };states[selected.id]?.phase==PackagePhase.INSTALLED }
            Text(tr("Готово языков: %@ из %@", "Languages ready: %@ of %@", (ready), (languages.size)),modifier=Modifier.testTag("voices.coverage"))
            if(progress.busy) { CatProgress(progress.fraction);Note(bytes(progress.receivedBytes)+tr(" из ")+bytes(progress.totalBytes));TextButton(contentPadding=GroupActionPadding,onClick={plan.ids.forEach(state.packages::pause)}) { Text(tr("Приостановить скачивание голосов")) } }
            else if(!progress.ready) { TextButton(contentPadding=GroupActionPadding,onClick={download(plan.ids)},enabled=restored,modifier=Modifier.testTag("voices.downloadAll")) { Text(tr("Скачать недостающие голоса")) };Note(bytes(progress.remainingBytes)) }
            Note(tr("Supertonic и OmniVoice — общие пакеты для нескольких языков. Остальные голоса скачиваются отдельно. Ваш выбор голоса сохраняется."));ErrorText(state)
        } }
        items(languages,key={it}) { language -> Group(if(language=="ban")tr("Балийский","Balinese") else IndexLanguages.byId[language]?.let { state.languageName(it.id) } ?: language) { voices.filter { it.supports(language) }.forEach { PackagePanel(state,it,states[it.id],download,language) } } }
        item { Note(tr("Голос скачивается только по нажатию. Образец создан этой же моделью заранее; время синтеза на вашем телефоне измеряется отдельно.")) }
    }
}
@Composable internal fun OcrModelsSheet(state:TranslatorState) {
    val states by state.packages.states.collectAsState();val download=rememberDownload(state)
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item { Group("Google ML Kit") {
            SettingRow(tr("Распознавание", "Text recognition"),tr("Встроено · без интернета", "Built in · offline"))
            Note(tr("Для поддерживаемых языков используется автоматически: латиница, китайский, японский, корейский и деванагари. Отдельная загрузка не нужна.", "Used automatically for supported languages: Latin, Chinese, Japanese, Korean and Devanagari. No additional download needed."))
            Note(tr("Русский — PP-OCR. Установите русский пакет и быстрый поиск текста mobile. Движок выбирается по исходному языку.", "Russian uses PP-OCR. Install the Russian pack and fast mobile text detector. The source language selects the engine."))
        } }
        items(state.packages.catalog.filter { it.category==PackageCategory.OCR },key={it.id}) { PackagePanel(state,it,states[it.id],download) }
    }
}
@Composable internal fun LanguageSetupSheet(state:TranslatorState,done:()->Unit) {
    var setup by rememberSaveable(stateSaver=androidx.compose.runtime.saveable.listSaver(save={listOf(it.primaryId,it.targetIds.joinToString(","),it.recognition,it.speech,it.extraPrimaryIds.joinToString(","))},restore={PackageLanguageSetup(it[0] as String,(it[1] as String).split(",").filter { id -> id.isNotEmpty() },it[2] as Boolean,it[3] as Boolean,(it[4] as String).split(",").filter { id -> id.isNotEmpty() })})) { mutableStateOf(state.languageSetup) }
    var started by rememberSaveable { mutableStateOf(false) }
    val states by state.packages.states.collectAsState();val restored by state.packages.restored.collectAsState()
    // Auto assembles translation by device class; an explicit choice is downloaded as selected.
    val selectedTranslation=state.translationModel
    val plan=state.setupPlan(setup)
    val progress=plan.summary(states)
    val download=rememberPackageDownload(state) {
        state.saveLanguageSetup(setup);state.markSetupCompleted();state.chooseLanguage(setup.primaryId,true)
        setup.targetIds.firstOrNull { it!=setup.primaryId }?.let { state.chooseLanguage(it,false) }
        started=true
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
            // Step 1: the device test runs before languages, so the plan already fits the device.
            Group(tr("Проверка устройства","Device check")) {
                if(state.probing || state.deviceClass==null) {
                    CatProgress()
                    Note(tr("Проверяю память и графический процессор, 3–5 секунд. Ничего не скачивается.","Checking memory and GPU, 3–5 seconds. Nothing is downloaded."))
                } else {
                    val estimate=state.estimatedTokensPerSecond("index")
                    Note(tr("Память: %.0f ГБ/с · GPU: %s · Index 9B с учётом нагрева: ~%.1f ток/с".format(state.deviceBandwidth,if(state.deviceGpuGbps>0)"%.0f ГБ/с".format(state.deviceGpuGbps) else "нет",estimate ?: 0.0),
                        "Memory: %.0f GB/s · GPU: %s · Index 9B with thermal margin: ~%.1f tokens/s".format(state.deviceBandwidth,if(state.deviceGpuGbps>0)"%.0f GB/s".format(state.deviceGpuGbps) else "none",estimate ?: 0.0)))
                    Text(if(state.strongDevice)tr("Рекомендуем: Index 9B — одна модель на все языки, лучшее качество.","Recommended: Index 9B — one model for all languages, best quality.")
                        else tr("Рекомендуем: OPUS для поддерживаемых пар + Index 2B для остальных — быстрее на этом устройстве.","Recommended: OPUS for supported pairs + Index 2B for the rest — faster on this device."),color=KatAccent,modifier=Modifier.testTag("setup.recommendation"))
                    TextButton(contentPadding=GroupActionPadding,onClick=state::runDeviceProbe,enabled=!started && !state.busy,modifier=Modifier.testTag("setup.probe")) { Text(tr("Проверить снова","Check again")) }
                }
            }
            if(state.probing || state.deviceClass==null)return@Column
            Note(tr("Выберите языки. Общие модели скачиваются один раз, остальные можно добавить позже."))
            Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                SetupLanguageColumn(true,setup,!started,Modifier.weight(1f)) { setup=it }
                SetupLanguageColumn(false,setup,!started,Modifier.weight(1f)) { setup=it }
            }
            ToggleRow(tr("Распознавание речи"),setup.recognition,enabled=!started,tag="setup.recognition") { setup=setup.copy(recognition=it) }
            ToggleRow(tr("Озвучивание перевода"),setup.speech,enabled=!started,tag="setup.speech") { setup=setup.copy(speech=it) }
            Group(tr("Нужные модели")) {
                plan.packages.forEach { pack -> SettingRow(if(pack.category==PackageCategory.TRANSLATION)tr("Перевод")+" · "+tr(pack.title) else tr(pack.title),bytes(pack.downloadBytes)) }
                if(selectedTranslation==AUTO_TRANSLATION)Note(state.estimatedTokensPerSecond("index").let { speed ->
                    val estimate=speed?.let { tr(" (оценка Index 9B: ~%.0f ток/с)".format(it)," (Index 9B estimate: ~%.0f tokens/s)".format(it)) } ?: ""
                    if(state.strongDevice)tr("Мощное устройство%@: перевод — Index 9B, одна модель на все языки.", "Powerful device%@: Index 9B translates all languages.", (estimate))
                    else tr("Устройство среднего класса%@: перевод — компактные модели OPUS для каждой пары; для пар без OPUS — Index 2B.", "Mid-range device%@: compact OPUS models per pair; Index 2B for pairs OPUS does not cover.", (estimate))
                })
                else Note(when(selectedTranslation) {
                    "opus" -> tr("Меньше объём загрузки и расход памяти. Перевод без интернета с английского на русский, украинский и белорусский и обратно. Качество сложных текстов может уступать Index.")
                    "index" -> tr("Index 9B — максимальное качество. Index 2B примерно в 3 раза быстрее. Модель перевода общая для нескольких языков.","Index 9B gives maximum quality. Index 2B is about 3× faster. One translation model serves several languages.")
                    else -> tr("Index 2B — быстрая модель для 150 языков. Для максимального качества выберите Index 9B. Модель перевода общая для нескольких языков.","Index 2B is a fast model for 150 languages. Select Index 9B for maximum quality. One translation model serves several languages.")
                })
                if(plan.missingRecognition.isNotEmpty())Note(tr("Без распознавания: ")+plan.missingRecognition.map { languageName(it) }.joinToString(", "))
                if(plan.missingSpeech.isNotEmpty())Note(tr("Без озвучки: ")+plan.missingSpeech.map { languageName(it) }.joinToString(", "))
            }
            if(selectedTranslation!=AUTO_TRANSLATION)Note(when(selectedTranslation) { "opus" -> tr("Меньше расход памяти, чем у моделей 4B–9B");"index" -> tr("RAM телефона: от 12 ГБ (ориентир)");else -> tr("Меньше памяти, чем у 9B","Uses less memory than 9B") })
            Note(tr("Можно свернуть приложение: загрузка продолжится. Разрешите уведомления, чтобы узнать о готовности моделей. Не закрывайте приложение смахиванием из списка недавних."))
            if(started)Text(when { progress.busy -> tr("Скачиваю выбранные пакеты…");progress.ready -> tr("Пакеты для перевода готовы");else -> tr("Загрузка не завершена. Проверьте подключение и продолжите скачивание.") },color=if(progress.ready)KatAccent else Muted)
            ErrorText(state)
        }
        Column(Modifier.fillMaxWidth().background(Grouped).padding(16.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if(started)CatProgress(progress.fraction)
            // Everything for this plan is installed and no download was started: Download is inactive.
            val alreadyInstalled=restored && !started && progress.ready
            Text(if(!restored)tr("Проверяю модели…") else if(alreadyInstalled)tr("Всё нужное уже скачано","Everything needed is already downloaded")
                else tr("Осталось скачать: ")+bytes(progress.remainingBytes)+" · "+tr("всего: ","total: ")+bytes(progress.totalBytes),modifier=Modifier.testTag("setup.bytes"))
            Note(tr("Уже установленные файлы не скачиваются повторно."))
            if(progress.busy)TextButton(contentPadding=GroupActionPadding,onClick={plan.ids.forEach(state.packages::pause)}) { Text(tr("Приостановить скачивание")) }
            else if(alreadyInstalled)Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Pill(tr("Скачать"),"setup.download",false) {}
                Pill(tr("Готово"),"setup.done",plan.isValid && !state.busy && !state.probing) {
                    state.saveLanguageSetup(setup);state.markSetupCompleted();state.chooseLanguage(setup.primaryId,true)
                    setup.targetIds.firstOrNull { it!=setup.primaryId }?.let { state.chooseLanguage(it,false) }
                    done()
                }
            }
            else Pill(if(started && progress.ready)tr("Готово") else tr("Скачать"),"setup.download",plan.isValid && restored && !state.busy && !state.probing) {
                if(started && progress.ready)done()
                else download(plan.ids)
            }
        }
    }
}
@Composable private fun SetupLanguageColumn(primary:Boolean,setup:PackageLanguageSetup,enabled:Boolean,modifier:Modifier,change:(PackageLanguageSetup)->Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val focus=androidx.compose.ui.platform.LocalFocusManager.current
    val uiLanguage=LocalUiLanguage.current
    Column(modifier,verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(if(primary)tr("Мои языки","My languages") else tr("Языки перевода"),fontWeight=FontWeight.SemiBold,fontSize=15.sp)
        BasicTextField(query,{query=it},singleLine=true,enabled=enabled,textStyle=TextStyle(color=Color.White,fontSize=15.sp),modifier=Modifier.fillMaxWidth().background(Grouped).padding(10.dp).testTag(if(primary)"setup.search.primary" else "setup.search.targets"),decorationBox={inner -> if(query.isEmpty())Text(tr("Поиск языка"),color=Muted,fontSize=14.sp);inner() })
        val rows=IndexLanguages.all.filter { (primary || it.id !in setup.primaryIds) && languageMatches(it,query,uiLanguage) }
        LazyColumn(Modifier.height(230.dp)) {
            items(rows,key={it.id}) { language ->
                val selected=if(primary)language.id in setup.primaryIds else language.id in setup.targetIds
                Row(Modifier.fillMaxWidth().heightIn(min=44.dp).clickable(enabled=enabled) {
                    focus.clearFocus()
                    change(if(primary) {
                        // Several own languages; at least one always stays selected.
                        val own=if(selected)setup.primaryIds-language.id else setup.primaryIds+language.id
                        if(own.isEmpty())setup else setup.copy(primaryId=own.first(),extraPrimaryIds=own.drop(1),targetIds=setup.targetIds-language.id)
                    } else setup.copy(targetIds=if(selected)setup.targetIds-language.id else setup.targetIds+language.id))
                }.testTag((if(primary)"setup.primary." else "setup.target.")+language.id),verticalAlignment=Alignment.CenterVertically) {
                    Text(languageName(language.id),modifier=Modifier.weight(1f),fontSize=14.sp)
                    if(selected)Text("✓",color=KatAccent)
                }
                HorizontalDivider(color=Grouped)
            }
        }
    }
}
@Composable internal fun ModelDetailsSheet(state:TranslatorState,id:String,navigate:(String)->Unit) {
    val pack=state.packages.catalog.firstOrNull { it.id==id } ?: return
    val context=LocalContext.current
    val info=remember { android.app.ActivityManager.MemoryInfo().also { context.getSystemService(android.app.ActivityManager::class.java).getMemoryInfo(it) } }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        item { Group(tr("На этом устройстве")) {
            SettingRow(tr("Всего RAM"),bytes(info.totalMem))
            Note(if(pack.backend=="opus")tr("Компактный офлайн-переводчик · меньше загрузка и расход памяти") else tr("Для поддерживаемых пар на Android рекомендуется OPUS Big. Index доступен для других языков.","OPUS Big is recommended for supported pairs on Android. Index is available for other languages."))
            Note(if(pack.backend=="opus")tr("Меньше объём загрузки и расход памяти. Перевод без интернета с английского на русский, украинский и белорусский и обратно. Качество сложных текстов может уступать Index.") else tr("Более длинный текст, другие приложения и одновременная работа с речью могут увеличить нагрузку. Качество оценивайте на нужных вам языках.","Longer text, other apps and speech processing can increase memory use. Assess quality in the languages you need."))
        } }
        item { Group(tr("Языки и качество")) {
            Row(Modifier.fillMaxWidth().clickable { navigate("modelLanguages:${pack.id}") }.padding(vertical=12.dp).testTag("model.languages.open"),verticalAlignment=Alignment.CenterVertically) {
                Text(tr("Доступные языки"),modifier=Modifier.weight(1f));Text(pack.languages.size.toString(),color=Muted);Text("  ›",color=Muted)
            }
            Note(tr("Заявлено авторами: ")+if(pack.backend=="opus" && pack.id==PackageCatalog.DEFAULT_TRANSLATION_ID)tr("35 языков через направления OPUS · этот пакет: английский ↔ русский, украинский, белорусский") else if(pack.backend=="opus")pack.title.substringAfter("· ") else tr("150 языков"))
            Note(tr("Качество зависит от языка и текста. Число языков само по себе не означает лучший перевод."))
            if(pack.backend!="opus")Note(tr("Список зависит от выбранной модели. Для речи нужны отдельные модели распознавания и голоса; для камеры — распознавание текста.","The list depends on the selected model. Speech needs separate recognition and voice models; the camera needs text recognition."))
            if(pack.sourceURL.isNotBlank())TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(pack.sourceURL)))}) { Text(tr("Источник: описание модели")) }
            if(pack.backend=="opus") {
                Note("Helsinki-NLP · CC BY 4.0")
                TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-zle-en")))}) { Text("OPUS-MT · ZLE → EN") }
                TextButton(contentPadding=GroupActionPadding,onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://huggingface.co/crash-sv/scribe-translate-ct2/tree/366ea5f4bd2bc417a7430006408a0c6cd72a9f91")))}) { Text(tr("Источник компактных файлов")) }
            }
        } }
        item { Group(tr("Память и скачивание")) {
            Note(when(pack.backend) { "opus" -> tr("Меньше расход памяти, чем у моделей 4B–9B");PackageCatalog.MULTILINGUAL_BACKEND -> tr("Меньше памяти, чем у 9B","Uses less memory than 9B");else -> tr("RAM телефона: от 12 ГБ (ориентир)") })
            SettingRow(tr("Файл модели"),bytes(pack.downloadBytes))
            Note(tr("Размер файла — место в хранилище, а не расход RAM. При работе нужна дополнительная память для перевода, распознавания и озвучки. Общая RAM телефона не равна лимиту приложения."))
            Note(tr("Рекомендация предварительная: учитывает общий объём RAM и наши проверки, но не гарантирует стабильность при любой нагрузке. На непроверенном устройстве начните с короткой фразы."))
        } }
    }
}
@Composable internal fun ModelLanguagesSheet(state:TranslatorState,id:String) {
    val pack=state.packages.catalog.firstOrNull { it.id==id } ?: return
    var query by rememberSaveable(id) { mutableStateOf("") }
    val locale=java.util.Locale.forLanguageTag(state.uiLanguage)
    val collator=remember(locale) { java.text.Collator.getInstance(locale) }
    val languages=IndexLanguages.all.filter { pack.supports(it.id) }.sortedWith { a,b -> collator.compare(state.languageName(a.id),state.languageName(b.id)) }
    val matches=languages.filter { languageMatches(it,query,state.uiLanguage) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal=16.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(tr(pack.title),fontWeight=FontWeight.SemiBold)
            Text(tr("Языки перевода в приложении: %@", "Translation languages in the app: %@", (languages.size)),modifier=Modifier.testTag("model.languages.count"))
            Note(tr("Распознавание речи, озвучка и перевод изображений могут поддерживать меньше языков."))
            BasicTextField(query,{query=it},singleLine=true,textStyle=TextStyle(color=Color.White,fontSize=16.sp),modifier=Modifier.fillMaxWidth().background(Grouped).padding(12.dp).testTag("model.languages.search"),decorationBox={inner -> if(query.isEmpty())Text(tr("Название или код языка"),color=Muted);inner() })
        }
        LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(horizontal=16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            if(matches.isEmpty())item { Note(tr("Язык не найден")) }
            items(matches,key={it.id}) { language ->
                Row(Modifier.fillMaxWidth().padding(vertical=6.dp).testTag("model.languages.row.${language.id}"),verticalAlignment=Alignment.CenterVertically) {
                    Text(language.flag,modifier=Modifier.width(42.dp),fontSize=23.sp)
                    Column { Text(languageName(language.id),fontSize=18.sp);Note(nativeLanguageName(language)) }
                }
            }
        }
    }
}
private fun nativeLanguageName(language:org.openoffline.translator.inference.IndexLanguage):String {
    val locale=java.util.Locale.forLanguageTag(language.id)
    return locale.getDisplayLanguage(locale).takeIf { it.isNotBlank() && it!=language.id } ?: language.english
}
private fun languageMatches(language:org.openoffline.translator.inference.IndexLanguage,query:String,uiLanguage:String):Boolean {
    fun normalize(value:String)=java.text.Normalizer.normalize(value,java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"),"").lowercase(java.util.Locale.ROOT)
    val match=normalize(query.trim())
    return listOf(language.id,language.russian,language.english,nativeLanguageName(language),UiStrings.languageName(language.id,language.russian,language.english,uiLanguage)).any { normalize(it).contains(match) }
}
/** One row per language pair; each checkbox is a direction backed by one OPUS model package.
 * Group models serve several pairs, so selecting a direction can satisfy others too. */
private data class OpusDirectionRow(val a:String,val b:String,val forward:OfflinePackage?,val backward:OfflinePackage?)
@Composable internal fun OpusDirectionsSheet(state:TranslatorState) {
    val states by state.packages.states.collectAsState()
    val restored by state.packages.restored.collectAsState()
    val download=rememberPackageDownload(state)
    val catalog=state.packages.catalog
    var query by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf(listOf<String>()) }
    val rows=remember(catalog) {
        val languages=PackageCatalog.opusLanguages(catalog).filter { it in IndexLanguages.byId }
        val pairs=mutableListOf<OpusDirectionRow>()
        for(a in languages) for(b in languages) if(a<b) {
            val forward=PackageCatalog.opusRoute(catalog,a,b)?.first;val backward=PackageCatalog.opusRoute(catalog,b,a)?.first
            if(forward!=null || backward!=null)pairs+=OpusDirectionRow(a,b,forward,backward)
        }
        // Russian and English pairs first, then by language name.
        pairs.sortedWith(compareBy<OpusDirectionRow>({ if("ru" in setOf(it.a,it.b)) 0 else if("en" in setOf(it.a,it.b)) 1 else 2 },{ IndexLanguages.byId[if(it.a=="ru"||it.a=="en")it.b else it.a]?.russian }))
    }
    fun installed(pack:OfflinePackage)=states[pack.id]?.phase==PackagePhase.INSTALLED
    val pending=selected.mapNotNull { id -> catalog.firstOrNull { it.id==id } }.filter { !installed(it) && it.unavailableReason==null }
    val total=pending.sumOf { it.downloadBytes }
    val busy=catalog.any { it.opusRoutes.isNotEmpty() && states[it.id]?.busy==true }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal=20.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Note(tr("Отметьте нужные направления. Каждое направление — отдельная модель OPUS около 240 МБ; одна модель может обслуживать несколько пар.","Select the directions you need. Each direction is a separate OPUS model of about 240 MB; one model can serve several pairs."))
            BasicTextField(query,{query=it},singleLine=true,textStyle=TextStyle(color=Color.White,fontSize=15.sp),modifier=Modifier.fillMaxWidth().background(Grouped).padding(10.dp).testTag("opus.search"),decorationBox={inner -> if(query.isEmpty())Text(tr("Поиск языка","Search language"),color=Muted,fontSize=14.sp);inner() })
        }
        val visible=rows.filter { row -> query.isBlank() || listOf(row.a,row.b).any { id -> IndexLanguages.byId[id]?.let { it.russian.contains(query,true) || it.english.contains(query,true) || state.languageName(it.id).contains(query,true) } == true } }
        LazyColumn(Modifier.weight(1f).testTag("opus.directions"),contentPadding=PaddingValues(horizontal=20.dp)) {
            items(visible,key={"${it.a}-${it.b}"}) { row ->
                Column(Modifier.fillMaxWidth().padding(vertical=6.dp)) {
                    Text(languageName(row.a)+" ↔ "+languageName(row.b),fontWeight=FontWeight.SemiBold,fontSize=15.sp)
                    for((from,to,pack) in listOf(Triple(row.a,row.b,row.forward),Triple(row.b,row.a,row.backward))) {
                        if(pack==null) { Note(languageName(from)+" → "+languageName(to)+" · "+tr("нет модели","no model"));continue }
                        val done=installed(pack)
                        val checked=done || pack.id in selected
                        Row(Modifier.fillMaxWidth().heightIn(min=40.dp).clickable(enabled=restored && !done && pack.unavailableReason==null) {
                            selected=if(pack.id in selected)selected-pack.id else selected+pack.id
                        }.testTag("opus.direction.$from-$to"),verticalAlignment=Alignment.CenterVertically) {
                            Text(if(checked)"☑" else "☐",color=if(checked)KatAccent else Muted,fontSize=18.sp)
                            Spacer(Modifier.width(10.dp))
                            Text(languageName(from)+" → "+languageName(to),modifier=Modifier.weight(1f),fontSize=14.sp)
                            Text(when {
                                done -> tr("установлено","installed")
                                states[pack.id]?.busy==true -> phaseName(states[pack.id]!!.phase)
                                pack.unavailableReason!=null -> tr("вручную","manual")
                                else -> bytes(pack.downloadBytes)
                            },color=if(done)KatAccent else Muted,fontSize=12.sp)
                        }
                    }
                }
                HorizontalDivider(color=Grouped)
            }
        }
        Column(Modifier.fillMaxWidth().background(Grouped).padding(16.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if(busy)CatProgress()
            Text(tr("К загрузке: ","To download: ")+bytes(total)+" · "+tr("моделей: ","models: ")+pending.size,modifier=Modifier.testTag("opus.total"))
            if(selected.any { id -> catalog.firstOrNull { it.id==id }?.unavailableReason!=null })Note(tr("Часть направлений пока устанавливается только вручную.","Some directions can only be installed manually for now."))
            Pill(tr("Скачать","Download"),"opus.download",restored && pending.isNotEmpty() && !busy) { download(pending.map { it.id });selected=emptyList() }
        }
    }
}
