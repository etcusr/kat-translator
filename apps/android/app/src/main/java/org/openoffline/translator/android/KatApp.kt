@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.ui.ExperimentalComposeUiApi::class)
package org.openoffline.translator.android

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.view.Surface
import android.view.MotionEvent
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.RequestDisallowInterceptTouchEvent
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import org.openoffline.translator.inference.IndexLanguages
import org.openoffline.translator.inference.OfflineMedia
import org.openoffline.translator.android.packages.*
import java.io.File
import java.text.BreakIterator
import java.text.DateFormat
import java.util.Date

val KatAccent=Color(0xFFC9FA33)
internal val Muted=Color(0xFF8E8E93)
private val Panel=Color(0xFF0D0D0D)
internal val Grouped=Color(0xFF1C1C1E)
private val LabelStyle=TextStyle(fontSize=17.sp)
private val LocalGroupBackground=compositionLocalOf { Grouped }
internal val LocalUiLanguage=compositionLocalOf { "en" }
@Composable internal fun tr(ru:String,en:String?=null,vararg args:Any?)=UiStrings.text(ru,en,LocalUiLanguage.current,*args)
@Composable internal fun languageName(id:String)=IndexLanguages.byId[id]?.let { UiStrings.languageName(it.id,it.russian,it.english,LocalUiLanguage.current) } ?: tr("Авто","Auto")
private fun flag(id:String)=IndexLanguages.byId[id]?.flag ?: "◎"
private fun countCharacters(text:String):Int { val iterator=BreakIterator.getCharacterInstance();iterator.setText(text);var n=0;while(iterator.next()!=BreakIterator.DONE)n++;return n }
private fun copy(context:Context,text:String) { (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Kat translator",text)) }
private fun share(context:Context,text:String) { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type="text/plain";putExtra(Intent.EXTRA_TEXT,text) },null)) }
internal fun shareFile(context:Context,file:File,mime:String) {
    val uri=FileProvider.getUriForFile(context,"${context.packageName}.files",file)
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type=mime;putExtra(Intent.EXTRA_STREAM,uri);clipData=ClipData.newRawUri(file.name,uri);addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) },null))
}

@Composable fun KatApp(state:TranslatorState,keepAwake:(Boolean)->Unit) {
    val restored by state.packages.restored.collectAsState()
    val packageStates by state.packages.states.collectAsState()
    LaunchedEffect(restored,packageStates,state.automaticLoad,state.translationModel,state.mode) { state.tryAutomaticPrepare() }
    var sheet by rememberSaveable { mutableStateOf("") }
    var reader by rememberSaveable { mutableStateOf("") }
    var readerLive by rememberSaveable { mutableStateOf(true) }
    var historyImage by rememberSaveable { mutableStateOf("") }
    var sheetStack by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var confirmation by rememberSaveable { mutableStateOf("") }
    val pageState=rememberSaveableStateHolder()
    // First run: device check, then languages; nothing is downloaded until the user confirms.
    LaunchedEffect(restored) {
        if(restored && !state.setupCompleted && !state.installed && sheet.isEmpty())sheet="setup"
    }
    var visitedPages by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }
    var retentionDraft by rememberSaveable { mutableStateOf<List<Int>?>(null) }
    val context=LocalContext.current;val focus=LocalFocusManager.current;val keyboard=LocalSoftwareKeyboardController.current
    fun leaveInput() { focus.clearFocus(force=true);keyboard?.hide() }
    fun saveRetention(cleanup:Boolean=true) { retentionDraft?.let { state.setHistoryLimits(it[0],it[1],cleanup);state.setMediaLimits("audio",it[2],it[3],cleanup);state.setMediaLimits("image",it[4],it[5],cleanup) } }
    fun open(value:String) { if(sheet=="history")state.stopHistoryPlayback();if(value !in visitedPages)visitedPages=visitedPages+value;if(value=="settings" && retentionDraft==null)retentionDraft=listOf(state.historyCount,state.historyDays,state.audioCount,state.audioDays,state.imageCount,state.imageDays);leaveInput();if(sheet.isNotEmpty() && sheet!=value)sheetStack=sheetStack+sheet;sheet=value }
    fun closeSheet(back:Boolean=false) {
        leaveInput();if(sheet=="setup")state.markSetupCompleted()
        val next=SheetNavigation.close(sheet,sheetStack,back)
        val previousRoutes=sheetStack+sheet
        val nextRoutes=next.parents+next.route
        if("settings" in previousRoutes && "settings" !in nextRoutes) { saveRetention();retentionDraft=null }
        if("history" in previousRoutes && "history" !in nextRoutes)state.stopHistoryPlayback()
        val removed=if(next.route.isEmpty())visitedPages else previousRoutes.filterNot { it in nextRoutes }
        removed.forEach(pageState::removeState)
        visitedPages=visitedPages.filterNot { it in removed }
        sheet=next.route;sheetStack=next.parents
    }
    LaunchedEffect(state.busy,state.recording) { keepAwake(state.busy || state.recording) }
    LaunchedEffect(state.mode) { leaveInput() }
    CompositionLocalProvider(LocalUiLanguage provides state.uiLanguage,LocalContentColor provides Color.White) {
    MaterialTheme(colorScheme=darkColorScheme(primary=KatAccent,background=Color.Black,surface=Grouped,onSurface=Color.White,onPrimary=Color.Black),typography=Typography(bodyLarge=LabelStyle,bodyMedium=LabelStyle.copy(fontSize=15.sp))) {
        Surface(Modifier.fillMaxSize().then(if(sheet.isNotEmpty() || state.busy || !restored)Modifier.clearAndSetSemantics {} else Modifier),color=Color.Black) {
            Box(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                if(state.mode=="camera") CameraWorkspace(state,::open,sheet.isEmpty()) else Column(Modifier.fillMaxSize().then(if(state.busy || sheet.isNotEmpty())Modifier.clearAndSetSemantics {} else Modifier)) {
                    Row(Modifier.fillMaxWidth().heightIn(min=52.dp).padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {
                        Text("Kat translator",fontSize=17.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.weight(1f))
                        Row(Modifier.clip(RoundedCornerShape(26.dp)).background(Color(0xFF202022))) {
                            if(state.showTechnical)GlyphButton("chart",tr("Отчёт и измерения","Diagnostics"),"toolbar.diagnostics",!state.busy && !state.recording) { open("diagnostics") }
                            GlyphButton("history",tr("История переводов"),"toolbar.history",!state.busy && !state.recording) { open("history") }
                            GlyphButton("settings",tr("Настройки"),"toolbar.settings",!state.busy && !state.recording) { open("settings") }
                            GlyphButton("models",tr("Модели"),"toolbar.models",!state.busy && !state.recording) { open("models") }
                        }
                    }
                    ModePicker(state) { leaveInput();if(it=="camera")state.previousMode=state.mode;state.mode=it }
                    if(state.showTechnical)Text(state.translationRuntimeLabel,color=Muted,fontSize=12.sp,modifier=Modifier.align(Alignment.CenterHorizontally).testTag("model.current"))
                    if(state.mode=="text") {
                        // The whole workspace scrolls, including both panels. No nested fixed-height editor traps the result behind IME.
                        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                            LanguageControls(state,::open)
                            TextPanel(state,true) { readerLive=true;reader=state.input;open("original") }
                            TextPanel(state,false) { readerLive=true;reader=state.output;open("translation") }
                            PlaybackControls(state);ErrorText(state)
                        }
                        Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=8.dp),horizontalArrangement=Arrangement.End,verticalAlignment=Alignment.CenterVertically) {
                            if(WindowInsets.ime.getBottom(LocalDensity.current)>0)GlyphButton("keyboard",tr("Скрыть клавиатуру"),"keyboard.hide") { leaveInput() }
                            if(state.installed && !state.modelReady)TextButton(onClick=state::prepare,modifier=Modifier.testTag("text.prepare")) { Text(tr("Подготовить модель","Prepare model")) }
                            Pill(if(state.installed)tr("Перевести") else tr("Скачать модели"),"text.translate",state.input.isNotBlank() || !state.installed) { leaveInput();if(state.installed)state.translate() else open("models") }
                        }
                    } else VoiceWorkspace(state,::open) { value,original -> readerLive=true;reader=value;open(if(original)"original" else "translation") }
                }
            }
        }
        if(sheet.isNotEmpty()) {
            val title=when(sheet) { "history"->tr("История переводов");"settings"->tr("Настройки");"models"->tr("Модели");"source"->tr("Исходный язык");"target"->tr("Язык перевода");"original"->tr("Оригинал");"translation"->tr("Перевод");"voices"->tr("Голоса");"setup"->tr("Ваши языки");"ocrModels"->tr("Распознавание");"cameraText"->tr("Перевод снимка");"historyImage"->tr("Изображение с переводом");"privacy"->tr("Конфиденциальность и точность");"licenses"->tr("Определение языка — лицензии");"diagnostics"->tr("Отчёт и измерения","Diagnostics");else->tr("О приложении") }
            BackHandler { closeSheet(back=true) }
            // One app window owns the editor, IME and navigation. No draggable sheet or
            // second window can inherit stale IME insets from the outgoing editor.
            val isReader=sheet=="original" || sheet=="translation"
            val isImageReader=sheet=="historyImage"
            val isSetup=sheet=="setup"
            val largeTitle=sheet in setOf("settings","models","history")
            val sheetColor=if(sheet=="settings")Color(0xFF1C1C1E) else Color.Black
            BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black.copy(alpha=.55f)),contentAlignment=Alignment.BottomCenter) {
                val fullScreen=isReader || isImageReader || isSetup
                // The rounded surface begins below the opaque status bar. The old
                // inner top padding put these corners behind that bar; moving the
                // surface by the same amount preserves header/content coordinates.
                val sheetTop=if(fullScreen)0.dp else maxOf(maxHeight*.04f,WindowInsets.safeDrawing.asPaddingValues().calculateTopPadding())
                // A sibling shield blocks the workspace, without consuming any child sheet gestures.
                Box(Modifier.matchParentSize().pointerInput(Unit) { detectTapGestures {} })
                Column(Modifier.widthIn(max=860.dp).fillMaxWidth().height(maxHeight-sheetTop).clip(RoundedCornerShape(topStart=24.dp,topEnd=24.dp)).background(sheetColor).windowInsetsPadding(WindowInsets.safeDrawing.only(if(isReader || isImageReader || isSetup)WindowInsetsSides.Horizontal+WindowInsetsSides.Vertical else WindowInsetsSides.Horizontal+WindowInsetsSides.Bottom)).imePadding().testTag("sheet.container").then(if(state.busy)Modifier.clearAndSetSemantics {} else Modifier)) {
                    Column(Modifier.fillMaxWidth().testTag("sheet.header")) {
                        Row(Modifier.fillMaxWidth().padding(start=20.dp,end=16.dp,top=8.dp,bottom=8.dp).heightIn(min=44.dp),verticalAlignment=Alignment.CenterVertically) {
                            if(sheetStack.isNotEmpty() && !isReader && !isImageReader)TextButton(onClick={closeSheet(back=true)},modifier=Modifier.testTag("sheet.back")) { Text("‹ "+tr("Назад","Back")) }
                            if(!largeTitle)Text(if(sheet=="opusDirections")tr("Направления OPUS","OPUS directions") else if(sheet.startsWith("modelLanguages:"))tr("Доступные языки") else if(sheet.startsWith("voices:"))tr("Голоса") else if(sheet.startsWith("modelInfo:"))state.packages.catalog.firstOrNull { it.id==sheet.substringAfter(':') }?.title ?: title else title,fontWeight=FontWeight.SemiBold,fontSize=17.sp,modifier=Modifier.weight(1f)) else Spacer(Modifier.weight(1f))
                            if(isReader)GlyphButton("copy",tr("Скопировать","Copy"),"reader.copy") { copy(context,if(readerLive) { if(sheet=="original")state.input else state.output } else reader) }
                            TextButton(onClick={closeSheet()},modifier=Modifier.clip(CircleShape).background(Color.White.copy(alpha=.07f)).border(1.dp,Color.White.copy(alpha=.1f),CircleShape).testTag("sheet.close"),contentPadding=PaddingValues(horizontal=18.dp,vertical=6.dp)) { Text(if(isSetup)tr("Позже") else if(isReader)tr("Свернуть","Close") else tr("Готово"),fontSize=17.sp) }
                        }
                        if(largeTitle)Text(title,fontSize=34.sp,fontWeight=FontWeight.Bold,modifier=Modifier.padding(start=20.dp,end=20.dp,bottom=12.dp))
                    }
                    HorizontalDivider(color=Grouped)
                    pageState.SaveableStateProvider(sheet) {
                    if(sheet=="source" || sheet=="target")LanguageSheet(state,sheet=="source",{open("voices:$it")}) { closeSheet() }
                    else if(sheet=="models")ModelsSheet(state,::open)
                    else if(sheet=="voices" || sheet.startsWith("voices:"))VoiceSettingsSheet(state,if(sheet.startsWith("voices:"))sheet.substringAfter(':') else null)
                    else if(sheet=="setup")LanguageSetupSheet(state) { state.markSetupCompleted();closeSheet() }
                    else if(sheet=="ocrModels")OcrModelsSheet(state)
                    else if(sheet=="opusDirections")OpusDirectionsSheet(state)
                    else if(sheet=="historyImage")HistoryImage(state.historyFile(historyImage),Modifier.weight(1f))
                    else if(sheet.startsWith("modelInfo:"))ModelDetailsSheet(state,sheet.substringAfter(':'),::open)
                    else if(sheet.startsWith("modelLanguages:"))ModelLanguagesSheet(state,sheet.substringAfter(':'))
                    else if(sheet=="history")HistorySheet(state,{confirmation=it}) { historyImage=it;open("historyImage") }
                    else Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
                        when(sheet) {
                            "original","translation" -> {
                                val content=if(readerLive) { if(sheet=="original")state.input else state.output } else reader
                                SelectionContainer { Text(content,fontSize=22.sp,lineHeight=30.sp,modifier=Modifier.testTag("reader.text")) }
                                Text(tr("Символов: %@", "Characters: %@", (countCharacters(content))),color=Muted,fontSize=12.sp,modifier=Modifier.align(Alignment.End).testTag("reader.count"))
                            }
                            "settings" -> CompositionLocalProvider(LocalGroupBackground provides Color(0xFF2C2C2E)) { SettingsSheet(state,::open,retentionDraft ?: listOf(state.historyCount,state.historyDays,state.audioCount,state.audioDays,state.imageCount,state.imageDays),{retentionDraft=it;saveRetention(cleanup=false)}) { confirmation="history" } }
                            "privacy" -> Group(tr("Конфиденциальность","Privacy")) {
                                Text(tr("Разработчик Kat translator не собирает пользовательские данные через приложение. Тексты, записи голоса, изображения и переводы обрабатываются на устройстве и автоматически разработчику не передаются.","The developer of Kat translator does not collect user data through the app. Text, voice recordings, images and translations are processed on your device and are not automatically sent to the developer."))
                                Text(tr("Модели скачиваются со сторонних серверов. Google ML Kit для распознавания текста на фото передаёт Google технические метрики. История, включая исходные записи речи при включённом сохранении аудио, хранится локально. Копирование и отправка используют системный буфер обмена и выбранное приложение.","Models are downloaded from third-party servers. Google ML Kit for image text recognition sends technical metrics to Google. History, including original recordings when audio saving is enabled, is stored locally. Copy and Share use the system clipboard and the app you choose."))
                                TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://etcusr.github.io/kat-translator/privacy/")))}) { Text(tr("Полная политика конфиденциальности","Full privacy policy")) }
                                Text("katlabs.dev@gmail.com")
                            }
                            "cameraText" -> {
                                Row { GlyphButton("clear",tr("Очистить перевод снимка"),"camera.clearTranslation") { state.clearCameraText();closeSheet(back=true) };Spacer(Modifier.weight(1f));GlyphButton("copy",tr("Скопировать перевод"),"camera.copyTranslation") { copy(context,state.output) } }
                                SelectionContainer { Text(state.output,fontSize=17.sp,modifier=Modifier.testTag("camera.translationText")) };if(state.showTechnical)state.timing?.let { TimingSummary(it) }
                            }
                            "licenses" -> Group(tr("Определение языка — лицензии")) { Text(tr("Определение языка предоставляется системным TextClassifier Android. Модели и лицензии управляются операционной системой.","Language detection is provided by Android’s system TextClassifier. Its models and licenses are managed by the operating system.")) }
                            "diagnostics" -> Group(tr("Измерения","Measurements")) { SelectionContainer { Text(state.diagnostics()) };TextButton(contentPadding=GroupActionPadding,onClick={share(context,state.diagnostics())}) { Text(tr("Экспортировать отчёт","Export report")) };ToggleRow("MTP",state.mtp,tag="settings.mtp",action=state::changeMtp);TextButton(onClick=state::unload) { Text(tr("Освободить память","Free memory")) } }
                            else -> Group("Kat translator") { Text("Android · Index-Translate 2B / 9B · llama.cpp");Text(tr("Локальный перевод текста, речи и изображений. Доступность языков распознавания и озвучки зависит от установленных моделей.","Local translation of text, speech and images. Recognition and speech languages depend on installed models.")) }
                        }
                    }
                    }
                }
            }
        }
        if(restored && state.busy && state.streamingOutput && sheet.isEmpty() && state.mode!="camera")StreamingBar(state)
        else if(!restored || state.busy && (state.mode!="camera" || sheet.isNotEmpty()))Processing(state,checkingPackages=!restored)
        if(confirmation.isNotEmpty())AlertDialog(onDismissRequest={confirmation=""},title={Text(if(confirmation=="history")tr("Очистить всю историю?") else tr("Удалить запись?","Delete entry?"))},text={Text(tr("Это действие нельзя отменить.","This cannot be undone."))},confirmButton={TextButton(onClick={if(confirmation=="history")state.clearHistory() else state.deleteHistory(confirmation);confirmation=""}) { Text(tr("Удалить"),color=Color(0xFFFF6961)) }},dismissButton={TextButton(onClick={confirmation=""}) { Text(tr("Отменить")) }})
    } }
}
@Composable private fun ModePicker(state:TranslatorState,choose:(String)->Unit) {
    Row(Modifier.padding(horizontal=20.dp,vertical=10.dp).fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color(0xFF232326)).padding(3.dp)) {
        listOf("voice" to tr("Голос"),"text" to tr("Текст"),"camera" to tr("Камера")).forEach { (id,title) ->
            Box(Modifier.weight(1f).heightIn(min=36.dp).clip(RoundedCornerShape(16.dp)).background(if(state.mode==id)Color(0xFF626267) else Color.Transparent).clickable(enabled=!state.busy && !state.recording) { choose(id) }.semantics { selected=state.mode==id;role=Role.Tab }.testTag("mode.$id"),contentAlignment=Alignment.Center) { Text(title,fontSize=14.sp,fontWeight=if(state.mode==id)FontWeight.SemiBold else FontWeight.Normal,modifier=Modifier.padding(vertical=4.dp)) }
        }
    }
}
@Composable private fun LanguageControls(state:TranslatorState,open:(String)->Unit) {
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
        LanguageButton(state.currentSource,true,Modifier.weight(1f),!state.recording) { open("source") }
        GlyphButton("swap",tr("Поменять языки местами"),"language.swap",!state.recording) { state.swap() }
        LanguageButton(state.target,false,Modifier.weight(1f),!state.recording) { open("target") }
    }
    ToggleRow(tr("Автоматически озвучивать"),state.automaticSpeech,tag="language.automaticSpeech",action=state::changeAutomaticSpeech)
    if(state.currentSource=="auto" && state.detectedSource!=null)Note(tr("Распознанный язык","Detected language")+": "+languageName(state.detectedSource!!))
}
@Composable private fun LanguageButton(id:String,source:Boolean,modifier:Modifier,enabled:Boolean=true,onClick:()->Unit) {
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(Panel).clickable(enabled=enabled,onClick=onClick).padding(12.dp).testTag(if(source)"language.source" else "language.target")) {
        Text(if(source)tr("С языка") else tr("На язык"),fontSize=12.sp,color=Muted);Spacer(Modifier.height(4.dp))
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(5.dp)) { Text(flag(id),fontSize=15.sp);Text(languageName(id),fontSize=14.sp,fontWeight=FontWeight.SemiBold,color=KatAccent,maxLines=1,modifier=Modifier.weight(1f));KatIcon("down",modifier=Modifier.size(12.dp)) }
    }
}
@Composable private fun TextPanel(state:TranslatorState,original:Boolean,expand:()->Unit) {
    val content=if(original)state.input else state.output;val suffix=if(original)"source" else "target";val context=LocalContext.current
    val audioPanel=state.mode=="voice"
    val recordedOriginal=original && audioPanel
    val playing=state.isTextPlaying(original)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(14.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            Text(if(recordedOriginal)tr("Оригинал")+" · "+state.currentSource.uppercase() else if(original)state.currentSource.uppercase() else state.target.uppercase(),fontSize=12.sp,fontWeight=FontWeight.SemiBold,color=Muted,modifier=Modifier.weight(1f))
            GlyphButton("expand",tr("Показать полностью"),"text.$suffix.expand",content.isNotBlank(),40,expand)
            if(!recordedOriginal)PlaybackSpeed(state,"text.$suffix.speed")
            GlyphButton(if(playing)"close" else "speaker",if(playing)tr("Остановить","Stop") else if(recordedOriginal)tr("Прослушать запись","Play recording") else if(original)tr("Озвучить оригинал") else tr("Озвучить перевод"),"text.$suffix.playback",playing || ((if(recordedOriginal)state.hasOriginalAudio else content.isNotBlank()) && !state.busy && !state.recording),40) { state.readText(original) }
            GlyphButton("copy",if(original)tr("Скопировать оригинал") else tr("Скопировать перевод"),"text.copy.$suffix",content.isNotBlank(),40) { copy(context,content) }
            GlyphButton("share",if(recordedOriginal)tr("Поделиться записью","Share recording") else if(audioPanel)tr("Поделиться аудио перевода","Share translated audio") else tr("Поделиться текстом","Share text"),"text.share.$suffix",if(audioPanel)(if(original)state.hasOriginalAudio else state.hasTranslatedAudio) && !state.busy && !state.recording else content.isNotBlank(),40) {
                if(audioPanel)state.exportAudio(original) { shareFile(context,it,"audio/wav") } else share(context,content)
            }
            GlyphButton("clear",if(original)tr("Очистить оригинал") else tr("Очистить перевод"),"text.clear.$suffix",content.isNotEmpty(),40) { if(original)state.clear() else state.clearOutput() }
        }
        val inputLabel=tr("Текст оригинала","Original text")
        if(original && state.mode=="text")BasicTextField(value=state.input,onValueChange={state.input=it},textStyle=LabelStyle.copy(color=Color.White),cursorBrush=SolidColor(KatAccent),modifier=Modifier.fillMaxWidth().heightIn(min=88.dp).testTag("text.source.input").semantics { contentDescription=inputLabel })
        else SelectionContainer { Text(if(content.isEmpty()) { if(original)tr("Здесь появится распознанный текст","Recognized text will appear here") else tr("Здесь появится перевод") } else content,color=if(content.isEmpty())Muted else Color.White,fontSize=17.sp,modifier=Modifier.fillMaxWidth().heightIn(min=72.dp).testTag(if(original)"voice.original.text" else "text.translation.text")) }
        if(!original && state.showTechnical)state.timing?.let { TimingSummary(it) }
        Text("${countCharacters(content)} "+tr("символов","characters"),fontSize=11.sp,color=Muted,modifier=Modifier.align(Alignment.End).testTag("text.$suffix.count"))
    }
}
@Composable private fun VoiceWorkspace(state:TranslatorState,open:(String)->Unit,reader:(String,Boolean)->Unit) {
    val context=LocalContext.current
    var holding by remember { mutableStateOf(false) };var permissionRequiresHold by remember { mutableStateOf(false) }
    val microphone=rememberRuntimePermission(Manifest.permission.RECORD_AUDIO) { if(!permissionRequiresHold || holding)state.beginRecording() }
    val audioImport=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(state::importAudio) }
    fun begin(requireHold:Boolean=false) { permissionRequiresHold=requireHold;microphone.request() }
    val holdTouchOwner=remember { RequestDisallowInterceptTouchEvent() }
    var heldPointer by remember { mutableIntStateOf(-1) }
    fun endHold(submit:Boolean) {
        if(!holding)return
        holding=false;heldPointer=-1;holdTouchOwner(false)
        if(submit)state.finishRecording() else if(state.recording)state.discardRecording()
    }
    DisposableEffect(state,state.recordingMode) {
        onDispose { endHold(submit=false) }
    }
    Column(Modifier.fillMaxWidth().testTag("voice.workspace").verticalScroll(rememberScrollState()).padding(20.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(16.dp)) {
        LanguageControls(state,open)
        if(!state.voiceReady && !state.recording) {
            Pill(if(state.installed)tr("Подготовить модель","Prepare model") else tr("Скачать модели для перевода","Download translation models"),"voice.prepare",!state.busy) {
                if(state.installed)state.prepare() else open("models")
            }
        }
        if(state.voiceReady || state.recording) {
        val label=if(state.recording)tr("Остановить запись","Stop recording") else tr("Начать запись","Start recording")
        Box(Modifier.size(116.dp).testTag("voice.record").semantics { contentDescription=label;role=Role.Button;onClick { if(state.recording)state.finishRecording() else begin();true } }
            .background(KatAccent.copy(alpha=.08f),CircleShape).border(2.dp,KatAccent,CircleShape)
            .then(if(state.recordingMode=="hold")Modifier.pointerInteropFilter(holdTouchOwner) { event ->
                // Raw Android actions retain CANCEL, which Compose pointer changes can
                // represent as an up. Own the stream so scrolling cannot cancel a hold.
                when(event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        holding=true;heldPointer=event.getPointerId(0)
                        holdTouchOwner(true)
                        begin(true)
                    }
                    MotionEvent.ACTION_UP -> endHold(submit=true)
                    MotionEvent.ACTION_POINTER_UP -> if(event.getPointerId(event.actionIndex)==heldPointer)endHold(submit=true)
                    MotionEvent.ACTION_CANCEL -> endHold(submit=false)
                }
                true
            } else Modifier.pointerInput(state.recordingMode) {
                detectTapGestures(onTap={ if(state.recording)state.finishRecording() else begin() })
            }),contentAlignment=Alignment.Center) { KatIcon(if(state.recording)"clear" else "mic",KatAccent,Modifier.size(42.dp)) }
        Text(if(state.recording)"%02d:%02d".format(state.recordingMillis/60000,state.recordingMillis/1000%60) else if(state.recordingMode=="hold")tr("Удерживать для записи") else tr("Нажать для старта / остановки"),fontSize=15.sp,color=Muted)
        }
        if(state.recording) {
            LinearProgressIndicator(progress={ (state.level*8).coerceIn(0f,1f) },modifier=Modifier.fillMaxWidth())
            Row { TextButton(onClick=state::pauseRecording) { Text(if(state.recordingPaused)tr("Продолжить","Resume") else tr("Пауза","Pause")) };TextButton(onClick=state::finishRecording) { Text(tr("Перевести")) };TextButton(onClick=state::discardRecording) { Text(tr("Отменить")) } }
        } else TextButton(onClick={audioImport.launch(arrayOf("audio/*"))},modifier=Modifier.testTag("voice.import")) { Text(tr("Открыть аудиофайл…","Open audio file…")) }
        if(!microphone.granted && microphone.asked)PermissionAccessNotice(tr("микрофону","microphone"),microphone,"voice.permission")
        state.previewMessage?.let { Note(it) }
        if(state.previewProcessing)Text(tr("Обрабатываю фразу…","Processing phrase…"),color=Muted,modifier=Modifier.testTag("voice.preview.processing"))
        TextPanel(state,false) { reader(state.output,false) }
        TextPanel(state,true) { reader(state.input,true) }
        PlaybackControls(state);ErrorText(state)
    }
}
@Composable internal fun PlaybackControls(state:TranslatorState) { if(state.playing)Row { TextButton(onClick=state::pausePlayback) { Text(if(state.playbackPaused)tr("Продолжить","Resume") else tr("Пауза","Pause")) };TextButton(onClick=state::stopPlayback) { Text(tr("Остановить","Stop")) };PlaybackSpeed(state,"playback.speed") } }
@Composable private fun PlaybackSpeed(state:TranslatorState,tag:String) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(verticalAlignment=Alignment.CenterVertically) {
            TextButton(onClick=state::cycleSpeed,contentPadding=PaddingValues(0.dp),modifier=Modifier.width(40.dp).testTag(tag)) { Text("×${state.speed}",fontSize=12.sp) }
            GlyphButton("down",tr("Выбрать скорость","Choose speed"),"$tag.choose",size=30) { expanded=true }
        }
        DropdownMenu(expanded,onDismissRequest={expanded=false}) {
            listOf(1f,1.25f,1.5f,2f).forEach { value ->
                DropdownMenuItem(text={Text("×$value")},onClick={state.setPlaybackSpeed(value);expanded=false},modifier=Modifier.testTag("$tag.$value"))
            }
        }
    }
}
@Composable internal fun PermissionAccessNotice(access:String,gate:RuntimePermissionGate,tag:String) {
    Text(if(gate.settingsRequired)tr("Нет доступа к %@. Нажмите, чтобы разрешить в настройках Android.", "No access to %@. Tap to allow it in Android settings.", (access)) else tr("Нужен доступ к %@. Нажмите, чтобы разрешить.", "Access to %@ is required. Tap to allow.", (access)),
        color=KatAccent,fontSize=15.sp,modifier=Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Panel).clickable(onClick=gate.request).padding(14.dp).testTag(tag))
}
@Composable internal fun ErrorText(state:TranslatorState) {
    if(state.mode=="voice")state.automaticRecognitionPackage?.let { pack ->
        val states by state.packages.states.collectAsState()
        val restored by state.packages.restored.collectAsState()
        if(restored && state.packages.installedPath(pack.id)==null) {
            val download=rememberPackageDownload(state)
            RecognitionDownloadNotice(pack.title,states[pack.id] ?: PackageStatus(),!state.busy) { download(listOf(pack.id)) }
        }
    }
    val request=state.missingVoice
    if(request!=null && request.workspace==state.mode && state.selectedVoice(request.language)==request.packageId) {
        val states by state.packages.states.collectAsState()
        val download=rememberPackageDownload(state)
        VoiceDownloadNotice(languageName(request.language),(states[request.packageId] ?: PackageStatus()).let { if(it.phase==PackagePhase.INSTALLED && state.packages.installedPath(request.packageId)==null)PackageStatus() else it },!state.busy) { download(listOf(request.packageId)) }
    }
    state.error?.let { Text(it,color=Color(0xFFFFB65C),fontSize=14.sp,modifier=Modifier.testTag("translation.error")) }
}
@Composable internal fun RecognitionDownloadNotice(model:String,status:PackageStatus,enabled:Boolean=true,download:()->Unit) {
    val message=when {
        status.busy -> tr("Скачиваю распознавание: %@ · %@%", "Downloading recognition: %@ · %@%", (model), ((status.progress*100).toInt()))
        status.phase==PackagePhase.ERROR -> tr("Не удалось скачать %@. Нажмите, чтобы повторить.", "Could not download %@. Tap to retry.", (model))
        else -> tr("Для выбранного языка нужен %@. Скачать распознавание — нажмите здесь.", "This language requires %@. Download recognition — tap here.", (model))
    }
    Text(message,color=KatAccent,fontSize=15.sp,modifier=Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Panel)
        .clickable(enabled=enabled && !status.busy,onClick=download).padding(14.dp).testTag("recognition.download.notice"))
}
@Composable internal fun VoiceDownloadNotice(language:String,status:PackageStatus,enabled:Boolean=true,download:()->Unit) {
    val message=when {
        status.phase==PackagePhase.INSTALLED -> tr("Озвучка для языка «%@» скачана. Нажмите динамик для воспроизведения.", "The %@ voice is downloaded. Tap the speaker to play.", (language))
        status.busy -> tr("Скачиваю озвучку: %@ · %@%", "Downloading %@ voice · %@%", (language), ((status.progress*100).toInt()))
        status.phase==PackagePhase.ERROR -> tr("Не удалось скачать озвучку для языка «%@». Нажмите, чтобы повторить.", "Could not download the %@ voice. Tap to retry.", (language))
        else -> tr("Озвучка для языка «%@» не скачана. Нажмите, чтобы скачать.", "The %@ voice is not downloaded. Tap to download.", (language))
    }
    Text(message,color=KatAccent,fontSize=15.sp,modifier=Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Panel)
        .clickable(enabled=enabled && !status.busy && status.phase!=PackagePhase.INSTALLED,onClick=download).padding(14.dp).testTag("voice.download.notice"))
}
@Composable internal fun GlyphButton(icon:String,label:String,tag:String,enabled:Boolean=true,size:Int=44,action:()->Unit) { Box(Modifier.size(size.dp).clip(CircleShape).clickable(enabled=enabled,role=Role.Button,onClick=action).semantics { contentDescription=label;if(!enabled)disabled() }.testTag(tag),contentAlignment=Alignment.Center) { KatIcon(icon,if(enabled)KatAccent else Muted.copy(alpha=.4f)) } }
@Composable internal fun TimingSummary(timing:ProcessingTiming) {
    val unit=tr(" с"," s")
    fun seconds(value:Double?)=value?.let { "%.2f".format(it)+unit } ?: "—"
    Text(listOf(tr("Распознавание","Recognition")+": "+seconds(timing.recognition),
        tr("Перевод","Translation")+": "+seconds(timing.translation),
        tr("Озвучка","Speech synthesis")+": "+seconds(timing.synthesis),
        tr("Всего","Total")+": "+seconds(timing.total)).joinToString(" · "),
        fontSize=12.sp,color=Muted,modifier=Modifier.testTag("processing.timing"))
}
@Composable internal fun Pill(title:String,tag:String,enabled:Boolean=true,action:()->Unit) { Box(Modifier.heightIn(min=44.dp).clip(CircleShape).background(if(enabled)KatAccent else KatAccent.copy(alpha=.12f)).clickable(enabled=enabled,role=Role.Button,onClick=action).testTag(tag).padding(horizontal=24.dp,vertical=12.dp),contentAlignment=Alignment.Center) { Text(title,color=if(enabled)Color.Black else KatAccent.copy(alpha=.65f),fontSize=17.sp,fontWeight=FontWeight.SemiBold) } }
@Composable private fun IosSwitch(value:Boolean,enabled:Boolean=true,tag:String="",changed:(Boolean)->Unit) { Box(Modifier.size(51.dp,31.dp).clip(CircleShape).background(if(value)KatAccent else Color(0xFF39393D)).toggleable(value,enabled=enabled,role=Role.Switch,onValueChange=changed).testTag(tag).padding(2.dp),contentAlignment=if(value)Alignment.CenterEnd else Alignment.CenterStart) { Box(Modifier.size(27.dp).background(Color.White,CircleShape)) } }
/** Text actions inside a Group start at the card's text edge, not 12 dp further in. */
internal val GroupActionPadding=PaddingValues(horizontal=0.dp,vertical=8.dp)
/** Short state labels (recommended, selected, ready) share one size. */
@Composable internal fun Status(text:String,color:Color=KatAccent) { Text(text,fontSize=14.sp,color=color) }
@Composable internal fun languageCount(count:Int):String {
    if(LocalUiLanguage.current!="ru")return tr("%@ языков",null,count)
    val word=when { count%100 in 11..14 -> "языков";count%10==1 -> "язык";count%10 in 2..4 -> "языка";else -> "языков" }
    return "$count $word"
}
@Composable internal fun Note(text:String) { Text(text,fontSize=13.sp,color=Muted,lineHeight=18.sp) }
@Composable internal fun Group(title:String,content:@Composable ColumnScope.()->Unit) { Column(verticalArrangement=Arrangement.spacedBy(8.dp)) { if(title.isNotEmpty())Text(title,fontSize=17.sp,fontWeight=FontWeight.SemiBold,color=Color.White);Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(LocalGroupBackground.current).testTag("ui.group").padding(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp),content=content) } }
@Composable internal fun SettingRow(title:String,value:String="",action:(()->Unit)?=null) { Row(Modifier.fillMaxWidth().heightIn(min=34.dp).then(if(action!=null)Modifier.clickable(onClick=action) else Modifier),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) { Text(title,fontSize=16.sp,modifier=Modifier.weight(1f));if(value.isNotEmpty())Text(value,fontSize=14.sp,color=Muted,textAlign=TextAlign.End);if(action!=null)KatIcon("next",Muted,Modifier.size(13.dp)) } }
@Composable internal fun ToggleRow(title:String,value:Boolean,enabled:Boolean=true,tag:String="",action:(Boolean)->Unit) { Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) { Text(title,fontSize=16.sp,color=if(enabled)Color.White else Muted,modifier=Modifier.weight(1f));IosSwitch(value,enabled,tag,action) } }
@Composable internal fun LanguageLegendRow(icon:String,label:String,id:String,badge:String?=null,available:Boolean=true) {
    Row(Modifier.fillMaxWidth().padding(vertical=4.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(32.dp,28.dp),contentAlignment=Alignment.Center) {
            KatIcon(icon,if(available)KatAccent else Muted.copy(alpha=.4f),Modifier.size(22.dp).testTag("language.legend.icon.$id"))
            if(badge!=null)Text(badge,fontSize=11.sp,color=KatAccent,modifier=Modifier.align(Alignment.BottomEnd).background(Grouped,CircleShape))
        }
        Note(label)
    }
}
@Composable private fun LanguageSheet(state:TranslatorState,source:Boolean,openVoice:(String)->Unit,done:()->Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var legend by rememberSaveable { mutableStateOf(false) }
    var pendingVoice by rememberSaveable { mutableStateOf("") }
    val download=rememberPackageDownload(state) { if(pendingVoice.isNotEmpty())openVoice(pendingVoice) }
    val states by state.packages.states.collectAsState()
    val restored by state.packages.restored.collectAsState()
    val catalog=state.packages.catalog
    val supported=if(state.translationModel=="opus")PackageCatalog.opusLanguages(catalog) else IndexLanguages.byId.keys
    val rows=IndexLanguages.all.filter { it.id in supported }.sortedBy { state.languageName(it.id) }
    val matches=rows.filter { query.isBlank() || it.id.contains(query,true) || it.russian.contains(query,true) || it.english.contains(query,true) || state.languageName(it.id).contains(query,true) }
    val favoriteRows=matches.filter { it.id in state.favorites }
    val favoriteTitle=tr("Избранные");val allTitle=tr("Все языки")
    Column(Modifier.fillMaxSize().padding(horizontal=20.dp)) {
        Row(Modifier.padding(vertical=12.dp).fillMaxWidth().background(Grouped,RoundedCornerShape(10.dp)).padding(12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            KatIcon("search",Muted,Modifier.size(18.dp))
            BasicTextField(query,{query=it},modifier=Modifier.weight(1f).testTag("language.search"),textStyle=LabelStyle.copy(color=Color.White),singleLine=true,cursorBrush=SolidColor(KatAccent),decorationBox={ inner -> if(query.isEmpty())Text(tr("Название или код языка"),color=Muted,fontSize=15.sp);inner() })
        }
        LazyColumn(Modifier.weight(1f).testTag("language.list"),verticalArrangement=Arrangement.spacedBy(4.dp)) {
            if(source && state.mode=="text")item {
                Row(Modifier.fillMaxWidth().heightIn(min=56.dp).clickable { state.chooseLanguage("auto",true);done() }.testTag("language.row.auto"),verticalAlignment=Alignment.CenterVertically) {
                    Text("◎",fontSize=23.sp,modifier=Modifier.width(36.dp));Text(tr("Авто"),modifier=Modifier.weight(1f));if(state.source=="auto")KatIcon("check")
                }
            }
            item {
                Column(Modifier.fillMaxWidth().background(Grouped,RoundedCornerShape(12.dp)).padding(12.dp)) {
                    Note((when(state.translationModel) { "opus" -> "OPUS-MT Big";"index2b" -> "Index-Translate 2B";else -> "Index-Translate 9B" })+tr(" · в текстовом режиме: %@", " · text mode: %@", (rows.size)))
                    TextButton(contentPadding=GroupActionPadding,onClick={legend=!legend},modifier=Modifier.testTag("language.legend")) { Text((if(legend)"⌄ " else "› ")+tr("О значках и поддержке языков")) }
                    if(legend) {
                        LanguageLegendRow("mic",tr("Распознавание речи поддерживается"),"recognition")
                        LanguageLegendRow("speaker",tr("Озвучка готова"),"ready")
                        LanguageLegendRow("speaker",tr("Озвучка доступна — голос нужно скачать"),"download",badge="↓")
                        LanguageLegendRow("speaker",tr("Проверяем скачанные файлы озвучки"),"checking",badge="◷")
                        LanguageLegendRow("speaker",tr("Озвучка недоступна"),"unavailable",available=false)
                        Note(tr("Нажмите на динамик, чтобы скачать голос и открыть его настройки."))
                        Note(tr("Новые языки подключены по списку модели. Качество перевода на телефоне ещё не проверено для каждой пары."))
                    }
                }
            }
            if(matches.isEmpty())item { Note(tr("Язык не найден")) }
            listOf(favoriteRows to favoriteTitle,matches.filterNot { it.id in state.favorites } to allTitle).forEach { (languages,title) ->
                if(languages.isNotEmpty())item { Text(title,color=Muted,fontSize=13.sp,modifier=Modifier.padding(top=16.dp,bottom=8.dp)) }
                items(languages,key={it.id}) { language ->
                    val id=language.id
                    val recognition=catalog.any { it.category==PackageCategory.RECOGNITION && it.unavailableReason==null && it.supports(id) }
                    val voice=catalog.firstOrNull { it.id==state.selectedVoice(id) && it.unavailableReason==null }
                    val voiceReady=voice!=null && states[voice.id]?.phase==PackagePhase.INSTALLED
                    val candidateSource=if(source)id else state.currentSource
                    val candidateTarget=if(source)state.target else id
                    val limitation=when {
                        state.translationModel=="opus" && candidateSource!="auto" && candidateSource!=candidateTarget && PackageCatalog.opusRoute(catalog,candidateSource,candidateTarget)==null -> tr("Для этой пары нет модели OPUS · выберите Index","No OPUS model for this pair · use Index")
                        state.mode=="voice" && candidateSource!="auto" && catalog.none { it.category==PackageCategory.RECOGNITION && it.unavailableReason==null && it.supports(candidateSource) } -> tr("Голосовой ввод недоступен · используйте текст")
                        state.mode=="camera" && candidateSource!="auto" && OcrRouting.mlKitScript(candidateSource)==null && catalog.none { it.category==PackageCategory.OCR && it.backend=="ocr" && it.supports(candidateSource) } -> tr("Камера не распознаёт · используйте текст")
                        else -> null
                    }
                    Row(Modifier.fillMaxWidth().heightIn(min=64.dp),verticalAlignment=Alignment.CenterVertically) {
                        Row(Modifier.weight(1f).clickable(enabled=limitation==null) { state.chooseLanguage(id,source);done() }.padding(vertical=8.dp).testTag("language.row.$id"),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                            Text(flag(id),fontSize=23.sp)
                            Column(Modifier.weight(1f)) { Text(languageName(id),fontSize=17.sp,color=if(limitation==null)Color.White else Muted);Text(language.english,fontSize=12.sp,color=Muted);limitation?.let { Note(it) } }
                            if(id==(if(source)state.currentSource else state.target))KatIcon("check",modifier=Modifier.size(16.dp))
                        }
                        KatIcon("mic",if(recognition)KatAccent else Muted.copy(alpha=.4f),Modifier.size(22.dp).testTag("language.speech.$id"))
                        Box {
                            GlyphButton("speaker",(if(voiceReady)tr("Голоса: ") else tr("Скачать голос: "))+languageName(id),"language.voice.$id",voice!=null && restored,size=40) { if(voiceReady)openVoice(id) else if(voice!=null) { pendingVoice=id;download(listOf(voice.id)) } }
                            if(voice!=null && !voiceReady)Text(if(restored)"↓" else "◷",fontSize=11.sp,modifier=Modifier.align(Alignment.BottomEnd).background(Color.Black,CircleShape))
                        }
                        TextButton(onClick={state.toggleFavorite(id)},contentPadding=PaddingValues(0.dp),modifier=Modifier.size(40.dp).testTag("language.favorite.$id")) { Text(if(id in state.favorites)"★" else "☆",fontSize=22.sp) }
                    }
                }
            }
        }
    }
}
@Composable private fun SettingsSheet(state:TranslatorState,navigate:(String)->Unit,retention:List<Int>,updateRetention:(List<Int>)->Unit,clear:()->Unit) {
    fun update(index:Int,value:Int) { updateRetention(retention.toMutableList().apply { this[index]=value }) }
    val context=LocalContext.current
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
    SettingsGroup("") { MenuSetting(tr("Язык приложения"),state.interfaceLanguage,listOf("system" to tr("Как в системе"),"ru" to "Русский","en" to "English","es" to "Español","tr" to "Türkçe"),"settings.interfaceLanguage",state::changeInterfaceLanguage) }
    SettingsGroup(tr("Управление записью")) {
        MenuSetting(tr("Кнопка микрофона"),state.recordingMode,listOf("hold" to tr("Удерживать для записи"),"toggle" to tr("Нажать для старта / остановки")),"settings.recordingMode",state::changeRecordingMode)
        SettingRow(tr("Остановка после тишины"),"${state.silenceSeconds} "+tr("с","s"))
        IosSlider(state.silenceSeconds,1,30,tr("Тишина до остановки записи в секундах"),"settings.recordingSilence",state::setSilence)
        StepperSetting(tr("Лимит записи"),state.recordingMinutes,1,30,"recording.limit.stepper",state::setRecordingLimit,"${state.recordingMinutes} "+tr("мин","min"))
    }
    Note(tr("При удержании запись идёт до отпускания кнопки или лимита. Остановка после тишины действует в режиме нажатия. Настройки применяются со следующей записи.","When holding, recording continues until release or the time limit. Silence stops recording in tap mode. Changes apply to the next recording."))
    SettingsGroup(tr("Распознавание речи")) {
        listOf("automatic" to tr("Авто"),"system" to tr("Android — на устройстве","Android — on device"),"ultra" to "Parakeet Ultra","whisper" to tr("Whisper (классический)")).forEach { (id,title) ->
            val enabled=id!="ultra" && (id!="system" || state.systemRecognitionAvailable)
            Row(Modifier.fillMaxWidth().heightIn(min=44.dp).clickable(enabled=enabled) { state.changeRecognitionPreference(id) }.testTag("settings.recognition.$id"),verticalAlignment=Alignment.CenterVertically) {
                Text(title,color=if(enabled)Color.White else Muted,modifier=Modifier.weight(1f))
                if(state.recognitionPreference==id && (id!="automatic" || state.selectedRecognition()==null))KatIcon("check")
            }
        }
        ToggleRow(tr("Исправлять дату и время"),state.whisperDateTimeRepair,tag="settings.whisperDateTimeRepair",action=state::changeWhisperDateTimeRepair)
        TextButton(contentPadding=GroupActionPadding,onClick={navigate("models")},modifier=Modifier.testTag("settings.recognition.models")) { Text(tr("Модели распознавания")) }
    }
    Note(tr("Авто: русский — GigaAM, английский — Parakeet v2, остальные языки — Whisper Q8. Один и тот же выбор используется при записи, импорте и повторной проверке. Если модель не скачана, приложение предложит её загрузить. Ручной выбор модели действует во всех режимах.","Auto: Russian uses GigaAM, English uses Parakeet v2, other languages use Whisper Q8. Recording, import and verification use the same selection. If the model is missing, the app offers a download. A manual model selection applies to every mode."))
    Note(tr("Whisper повторно проверяет неоднозначные дату и время в русской речи. Может увеличить ожидание."))
    Note(tr("Parakeet Ultra использует Apple CoreML и недоступен на Android.","Parakeet Ultra requires Apple CoreML and is unavailable on Android."))
    SettingsGroup(tr("Экспериментально")) {
        ToggleRow(tr("Обрабатывать во время записи"),state.recordingPreprocessing,tag="settings.recordingPreprocessing",action=state::changeRecordingPreprocessing)
        if(state.recordingPreprocessing)ToggleRow(tr("Проверять текст после записи"),state.recordingVerification,tag="settings.recordingPreviewVerification",action=state::changeRecordingVerification)
    }
    Note(tr("Готовить перевод законченных фраз заранее. Озвучка начнётся после остановки. На Android пока для Whisper с Index без экономии памяти; возможны ошибки на стыках фраз.","Prepare translations of completed phrases. Speech starts after recording stops. On Android this requires Whisper and Index with memory saving off; phrase boundaries may contain errors."))
    if(state.recordingPreprocessing)Note(tr("Проверка повторно распознаёт запись и обновляет изменившиеся фразы перед озвучкой. Увеличивает ожидание и не гарантирует точность перевода."))
    SettingsGroup(tr("Озвучка")) { SettingRow(tr("Голоса и образцы"),action={navigate("voices")}) }
    Note(tr("Образцы доступны до скачивания и смены голоса."))
    SettingsGroup(tr("Память")) {
        ToggleRow(tr("Загружать модель при запуске"),state.automaticLoad,tag="settings.automaticModelLoad",action=state::changeAutomaticLoad)
        ToggleRow(tr("Экономия памяти"),state.memorySaving,tag="settings.memorySaving",action=state::changeMemorySaving)
    }
    Note(tr("Подготовить выбранную скачанную модель при открытии приложения. В режиме экономии памяти перевод загружается только перед запросом."))
    Note(tr("Выгружать модели между этапами. Меньше расход памяти, но больше ожидание загрузки."))
    SettingsGroup(tr("Текстовая история")) {
        ToggleRow(tr("Сохранять текст переводов"),state.recordHistory,tag="settings.recordText",action=state::setHistory)
        RetentionEditor(tr("Хранить переводов"),"text",retention[0],retention[1],{update(0,it)},{update(1,it)})
    }
    Note(tr("Если отключить, новый текст не попадёт в историю. Сохранённые записи останутся."))
    SettingsGroup(tr("Озвученные переводы")) {
        ToggleRow(tr("Сохранять аудио переводов"),state.recordAudio,tag="history.recordAudio",action=state::changeRecordAudio)
        RetentionEditor(tr("Хранить аудиофайлов"),"audio",retention[2],retention[3],{update(2,it)},{update(3,it)})
    }
    Note(tr("Отключение сохранения не мешает озвучке. Ранее сохранённые аудиофайлы останутся. Сохраняются озвучка и исходная запись микрофона.","Turning saving off does not disable speech. Existing audio files remain. Synthesized speech and the original microphone recording are saved."))
    SettingsGroup(tr("Изображения с переводом")) {
        ToggleRow(tr("Сохранять изображения с переводом"),state.recordImages,tag="history.recordImages",action=state::changeRecordImages)
        RetentionEditor(tr("Хранить изображений"),"image",retention[4],retention[5],{update(4,it)},{update(5,it)})
    }
    Note(tr("Готовые изображения сохраняются после перевода. Исходные файлы не изменяются. Хранение картинок и распознанного текста настраивается отдельно."))
    Note(tr("Настройки сохраняются автоматически. Очистка по новым лимитам выполняется при закрытии настроек. 0 дней отключает удаление по возрасту.","Settings are saved automatically. Cleanup using the new limits runs when settings are closed. Zero days disables deletion by age."))
    SettingsGroup("") { TextButton(contentPadding=GroupActionPadding,onClick=clear,modifier=Modifier.testTag("settings.clearHistory")) { Text(tr("Очистить историю"),color=Color(0xFFFF6961)) } }
    Note(tr("Удалить все сохранённые переводы, аудиофайлы и изображения. Настройки сохранения останутся прежними."))
    SettingsGroup(tr("Интерфейс")) { ToggleRow(tr("Показывать диагностику"),state.showTechnical,tag="settings.technical",action=state::setTechnical) }
    Note(tr("Показывать на главном экране значок с расходом памяти и времени обработки."))
    SettingsGroup(tr("О приложении")) {
        Text("Kat translator",fontWeight=FontWeight.SemiBold)
        Note(tr("Офлайн-переводчик голоса, текста и изображений. ИИ-модели работают на вашем Android после скачивания нужных пакетов.","Offline voice, text and image translator. AI models run on your Android device after downloading the required packages."))
        val version=remember { context.packageManager.getPackageInfo(context.packageName,0) }
        var versionCopied by remember { mutableStateOf(false) }
        LaunchedEffect(versionCopied) { if(versionCopied) { kotlinx.coroutines.delay(3000);versionCopied=false } }
        Column(Modifier.fillMaxWidth().clickable { copy(context,"Kat translator\n${version.versionName} (${version.longVersionCode})");versionCopied=true }.testTag("settings.copyVersion")) {
            SettingRow(tr("Версия"),version.versionName.orEmpty());SettingRow(tr("Сборка"),version.longVersionCode.toString())
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) { KatIcon(if(versionCopied)"check" else "copy");Note(if(versionCopied)tr("Скопировано","Copied") else tr("Скопировать версию и сборку","Copy version and build")) }
        }
        SettingRow(tr("Определение языка — лицензии"),action={navigate("licenses")})
        SettingRow(tr("Конфиденциальность и точность"),action={navigate("privacy")})
    }
    }
}
@Composable private fun SettingsGroup(title:String,content:@Composable ColumnScope.()->Unit) {
    Column(Modifier.padding(top=if(title.isEmpty())0.dp else 20.dp)) { Group(title,content) }
}
@Composable internal fun MenuSetting(title:String,value:String,options:List<Pair<String,String>>,tag:String,choose:(String)->Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box(Modifier.testTag(tag)) {
        SettingRow(title,options.firstOrNull { it.first==value }?.second.orEmpty()) { expanded=true }
        DropdownMenu(expanded,onDismissRequest={expanded=false}) {
            options.forEach { (id,label) -> DropdownMenuItem(text={Text(label)},onClick={choose(id);expanded=false},modifier=Modifier.testTag("$tag.$id"),trailingIcon={if(id==value)KatIcon("check")}) }
        }
    }
}
/** Native Slider semantics/keyboard/touch behavior with the current iOS track and thumb. */
@Composable private fun IosSlider(value:Int,min:Int,max:Int,label:String,tag:String,change:(Int)->Unit) {
    val fraction=((value-min).toFloat()/(max-min)).coerceIn(0f,1f)
    Slider(
        value=value.toFloat(),onValueChange={change(kotlin.math.round(it).toInt())},
        valueRange=min.toFloat()..max.toFloat(),steps=(max-min-1).coerceAtLeast(0),
        modifier=Modifier.fillMaxWidth().height(40.dp).testTag(tag).semantics { contentDescription=label },
        thumb={Box(Modifier.size(28.dp).background(Color.White,CircleShape).border(.5.dp,Color(0xFFE4E4E7),CircleShape))},
        track={Canvas(Modifier.fillMaxWidth().height(4.dp)) {
            val middle=size.height/2
            drawLine(Color(0xFF5A5A5E),androidx.compose.ui.geometry.Offset(0f,middle),androidx.compose.ui.geometry.Offset(size.width,middle),size.height,androidx.compose.ui.graphics.StrokeCap.Round)
            drawLine(KatAccent,androidx.compose.ui.geometry.Offset(0f,middle),androidx.compose.ui.geometry.Offset(size.width*fraction,middle),size.height,androidx.compose.ui.graphics.StrokeCap.Round)
        }}
    )
}
@Composable private fun StepperSetting(title:String,value:Int,min:Int,max:Int,tag:String,change:(Int)->Unit,label:String=value.toString()) {
    Row(Modifier.fillMaxWidth().testTag(tag),verticalAlignment=Alignment.CenterVertically) {
        Text(title,modifier=Modifier.weight(1f));Text(label,color=Muted,modifier=Modifier.padding(end=12.dp))
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha=.08f)),verticalAlignment=Alignment.CenterVertically) {
            TextButton(onClick={change(value-1)},enabled=value>min,contentPadding=PaddingValues(0.dp),modifier=Modifier.size(44.dp,34.dp).testTag("$tag.minus")) { Text("−",fontSize=22.sp) }
            Box(Modifier.width(1.dp).height(20.dp).background(Muted.copy(alpha=.4f)))
            TextButton(onClick={change(value+1)},enabled=value<max,contentPadding=PaddingValues(0.dp),modifier=Modifier.size(44.dp,34.dp).testTag("$tag.plus")) { Text("+",fontSize=22.sp) }
        }
    }
}
@Composable private fun RetentionEditor(title:String,kind:String,count:Int,days:Int,changeCount:(Int)->Unit,changeDays:(Int)->Unit) {
    Row(verticalAlignment=Alignment.CenterVertically) {
        Text(title,modifier=Modifier.weight(1f))
        BasicTextField(count.toString(),{it.toIntOrNull()?.let { number -> changeCount(number.coerceIn(0,10000)) }},singleLine=true,textStyle=LabelStyle.copy(color=Color.White,textAlign=TextAlign.End),keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=androidx.compose.ui.text.input.KeyboardType.Number),modifier=Modifier.width(80.dp).testTag("settings.${kind}Count"))
    }
    StepperSetting(if(count==0)tr("Без ограничения") else tr("Последние %@", "Last %@", (count)),count,0,10000,"settings.${kind}Count.stepper",changeCount,"")
    Text(if(days==0)tr("Не удалять по возрасту") else tr("Хранить %@ дней", "Keep for %@ days", (days)),fontSize=15.sp)
    IosSlider(days,0,365,tr("Хранение в днях","Retention in days"),"settings.${kind}Days",changeDays)
}
@Composable private fun HistorySheet(state:TranslatorState,delete:(String)->Unit,viewImage:(String)->Unit) {
    val context=LocalContext.current
    LazyColumn(Modifier.fillMaxSize().testTag("history.list"),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
    if(state.history.isEmpty())item { Column(Modifier.fillMaxWidth().padding(vertical=40.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(12.dp)) {
        KatIcon("history",Muted,Modifier.size(44.dp));Text(tr("История пока пуста"),fontSize=22.sp,fontWeight=FontWeight.SemiBold);Note(tr("Сохранение текста, аудио и изображений можно включить в настройках."))
    }
    }
    items(state.history,key={it.id}) { entry -> Group("") {
        Row(verticalAlignment=Alignment.CenterVertically) {
            Text(if(entry.translated.isBlank() && entry.originalAudio!=null)tr("Запись оригинала")+" · "+languageName(entry.source) else languageName(entry.source)+" → "+languageName(entry.target),fontSize=15.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.weight(1f))
            Text(DateFormat.getDateTimeInstance(DateFormat.SHORT,DateFormat.SHORT).format(Date(entry.time)),fontSize=11.sp,color=Muted)
        }
        state.historyFile(entry.image)?.let { file ->
            HistoryImage(file,Modifier.fillMaxWidth().height(180.dp).clickable { viewImage(file.name) },thumbnail=true)
            TextButton(onClick={shareFile(context,file,"image/png")},modifier=Modifier.testTag("history.shareImage.${entry.id}")) { Text(tr("Поделиться изображением")) }
        }
        if(entry.original.isNotEmpty() || entry.translated.isNotEmpty()) {
            SelectionContainer { Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(entry.original,color=Muted,modifier=Modifier.testTag("history.original.${entry.id}"))
                if(entry.translated.isNotEmpty())Text(entry.translated,modifier=Modifier.testTag("history.translation.${entry.id}"))
            } }
            if(entry.translated.isNotEmpty())TextButton(onClick={copy(context,entry.translated)}) { Text(tr("Скопировать перевод")) }
            if(entry.original.isNotEmpty())TextButton(onClick={copy(context,entry.original)}) { Text(tr("Скопировать оригинал")) }
        } else Note(tr("Текст не сохранён или удалён по настройкам хранения"))
        listOf(entry.audio to tr("Послушать"),entry.originalAudio to tr("Воспроизвести запись оригинала")).forEach { (name,title) ->
            state.historyFile(name)?.let { file ->
                if(state.playingFile==file.name && state.playing)PlaybackControls(state)
                else TextButton(onClick={state.playHistory(file.name)},modifier=Modifier.testTag("history.playback.${file.name}")) { Text(title) }
                TextButton(onClick={shareFile(context,file,"audio/wav")},modifier=Modifier.testTag("history.shareAudio.${file.name}")) { Text(if(name==entry.originalAudio)tr("Поделиться записью оригинала") else tr("Поделиться озвучкой")) }
            }
        }
        TextButton(onClick={delete(entry.id)},modifier=Modifier.testTag("history.delete.${entry.id}")) { Text(tr("Удалить запись"),color=Color(0xFFFF6961)) }
    } }
    }
}
@Composable private fun HistoryImage(file:File?,modifier:Modifier=Modifier,thumbnail:Boolean=false) {
    val bitmap by produceState<android.graphics.Bitmap?>(null,file?.path) {
        value=kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            file?.let {
                val bounds=android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds=true }
                android.graphics.BitmapFactory.decodeFile(it.path,bounds)
                var sample=1
                while(maxOf(bounds.outWidth,bounds.outHeight)/sample>2048)sample*=2
                android.graphics.BitmapFactory.decodeFile(it.path,android.graphics.BitmapFactory.Options().apply { inSampleSize=sample })
            }
        }
    }
    Box(modifier.fillMaxWidth(),contentAlignment=Alignment.Center) {
        bitmap?.let { if(thumbnail)Image(it.asImageBitmap(),tr("Изображение с переводом"),modifier=Modifier.fillMaxSize()) else ZoomablePicture(it,modifier=Modifier.fillMaxSize().testTag("history.image.reader")) }
    }
}
@Composable private fun categoryName(category:PackageCategory)=when(category) { PackageCategory.TRANSLATION->tr("Перевод");PackageCategory.RECOGNITION->tr("Распознавание речи");PackageCategory.VOICE->tr("Голоса","Voices");PackageCategory.OCR->"OCR" }
@Composable internal fun phaseName(phase:PackagePhase)=when(phase) { PackagePhase.ABSENT->tr("Не установлено","Not installed");PackagePhase.QUEUED->tr("В очереди","Queued");PackagePhase.DOWNLOADING->tr("Скачивание","Downloading");PackagePhase.PAUSED->tr("Пауза","Paused");PackagePhase.VERIFYING->tr("Проверка","Verifying");PackagePhase.INSTALLING->tr("Установка","Installing");PackagePhase.INSTALLED->tr("Установлено","Installed");PackagePhase.ERROR->tr("Ошибка","Error") }
@Composable private fun CameraWorkspace(state:TranslatorState,open:(String)->Unit,visible:Boolean) {
    val context=LocalContext.current
    val lifecycle=androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var cameraStatus by remember { mutableStateOf(org.openoffline.translator.android.camera.CameraStatus()) }
    var cameraRef by remember { mutableStateOf<org.openoffline.translator.android.camera.LiveCamera?>(null) }
    var zoom by remember { mutableFloatStateOf(1f) }
    val camera=remember {
        org.openoffline.translator.android.camera.LiveCamera(context,{cameraStatus=it}) { frame ->
            val owner=cameraRef;val revision=frame.revision
            state.receiveCameraFrame(frame) { owner?.revision==revision }
        }.also { cameraRef=it }
    }
    val cameraPermission=rememberRuntimePermission(Manifest.permission.CAMERA)
    val permissionGranted=cameraPermission.granted
    LaunchedEffect(Unit) {
        if(!permissionGranted && !cameraPermission.settingsRequired && state.image==null)cameraPermission.request()
    }
    DisposableEffect(camera) { onDispose { state.stopLiveCamera();camera.close();cameraRef=null } }
    DisposableEffect(camera,lifecycle,permissionGranted,state.image) {
        val observer=androidx.lifecycle.LifecycleEventObserver { _,event ->
            if(event==androidx.lifecycle.Lifecycle.Event.ON_STOP) { state.stopLiveCamera();camera.stop() }
            if(event==androidx.lifecycle.Lifecycle.Event.ON_START && permissionGranted && state.image==null)camera.start()
        }
        lifecycle.addObserver(observer)
        if(permissionGranted && state.image==null && lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED))camera.start() else camera.stop()
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(camera,state.busy,state.image,visible) { camera.setFrameDelivery(visible && !state.busy && state.image==null);if(!visible)state.stopLiveCamera() }
    val gallery=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { it?.let(state::loadImage) }
    fun close() { state.cancel();state.stopLiveCamera();camera.stop();state.mode=state.previousMode }
    BackHandler { close() }
    val frozen=state.image!=null
    val shutter:@Composable ()->Unit={
        Column(Modifier.width(80.dp).clickable(enabled=!state.busy && !cameraStatus.capturing) {
            if(!permissionGranted)cameraPermission.request()
            else if(frozen)state.resumeCamera()
            else if(!cameraStatus.active)camera.start()
            else camera.capture { result -> result.onSuccess(state::acceptCameraPhoto).onFailure { if(lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED))state.reportError(state.text("Не удалось сделать снимок. Повторите попытку.","Could not take a photo. Try again.")) } }
        }.testTag("camera.capture"),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Box(Modifier.size(60.dp).border(3.dp,Color.White,CircleShape),contentAlignment=Alignment.Center) {
                if(!frozen && cameraStatus.active)Box(Modifier.size(48.dp).background(Color.White,CircleShape)) else KatIcon("image",Color.White,Modifier.size(26.dp))
            }
            Text(if(frozen)tr("Ещё фото") else if(!cameraStatus.active)tr("Запустить") else tr("Снять"),fontSize=12.sp,fontWeight=FontWeight.SemiBold)
        }
    }
    val galleryButton:@Composable ()->Unit={
        Column(Modifier.width(80.dp).heightIn(min=72.dp).clickable(enabled=!state.busy && !cameraStatus.capturing) { gallery.launch("image/*") }.testTag("camera.gallery"),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
            KatIcon("image",modifier=Modifier.size(26.dp));Text(tr("Галерея"),fontSize=12.sp)
        }
    }
    val languages:@Composable RowScope.()->Unit={
        LanguageButton(state.currentSource,true,Modifier.weight(1f),!state.busy) { open("source") }
        GlyphButton("swap",tr("Поменять языки местами"),"language.swap",!state.busy,size=36) { state.swap() }
        LanguageButton(state.target,false,Modifier.weight(1f),!state.busy) { open("target") }
    }
    val actions:@Composable ()->Unit={
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            TextButton(onClick=state::saveCameraToGallery,enabled=state.output.isNotBlank() && !state.busy,modifier=Modifier.testTag("camera.save")) { Text(tr("Сохранить")) }
            Spacer(Modifier.weight(1f))
            GlyphButton("share",tr("Поделиться снимком"),"camera.share",state.output.isNotBlank() && !state.busy) { state.exportPicture { shareFile(context,it,"image/png") } }
            TextButton(onClick={open("cameraText")},enabled=state.output.isNotBlank(),modifier=Modifier.testTag("camera.text")) { Text("≡",fontSize=28.sp) }
        }
    }
    val status:@Composable ()->Unit={
        Text(if(state.busy)state.status else if(frozen) { state.cameraNotice ?: if(state.output.isBlank())tr("Текст не найден") else tr("Перевод снимка готов") } else state.liveCameraMessage ?: tr("Наведите камеру на текст"),fontSize=12.sp,maxLines=2,modifier=Modifier.testTag("camera.status"))
        if(cameraStatus.error!=null)Text(tr("Камера недоступна. Повторите попытку или откройте галерею.","Camera unavailable. Try again or open the gallery."),fontSize=12.sp,color=Color(0xFFFFB65C),maxLines=2)
        if(!permissionGranted)PermissionAccessNotice(tr("камере","camera"),cameraPermission,"camera.permission")
        ErrorText(state)
    }
    val zoomButtons:@Composable ()->Unit={
        listOf(1f,2f).forEach { factor -> TextButton(onClick={zoom=factor;camera.setZoom(factor)},enabled=factor<=cameraStatus.maxZoom,modifier=Modifier.size(44.dp).clip(CircleShape).background(if(zoom==factor)Color.White.copy(alpha=.25f) else Color.Transparent).testTag(if(factor==1f)"camera.zoom1" else "camera.zoom2")) { Text("${factor.toInt()}×",color=Color.White) } }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
        val landscape=maxWidth>maxHeight
        if(frozen) {
            ZoomablePicture(state.image!!,state.ocrBlocks,state.translatedBlocks,Modifier.fillMaxSize().testTag("camera.frozen"))
        } else {
            AndroidView(factory={camera.preview},modifier=Modifier.fillMaxSize().testTag("camera.preview").pointerInput(camera) { detectTapGestures { point -> camera.focus(point.x/size.width,point.y/size.height) } })
            state.liveCameraOverlay?.let { Image(it.asImageBitmap(),tr("Перевод"),contentScale=androidx.compose.ui.layout.ContentScale.Crop,modifier=Modifier.fillMaxSize()) }
        }
        if(landscape) {
            Row(Modifier.fillMaxSize().padding(horizontal=12.dp,vertical=8.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.Black.copy(alpha=.75f)).padding(4.dp),verticalAlignment=Alignment.CenterVertically) {
                        GlyphButton("close",tr("Закрыть камеру"),"camera.close") { close() };languages()
                        GlyphButton("history",tr("История переводов"),"camera.history") { open("history") }
                        GlyphButton("settings",tr("Настройки распознавания"),"camera.models") { open("ocrModels") }
                    }
                    Spacer(Modifier.weight(1f))
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.Black.copy(alpha=.7f)).padding(8.dp)) {
                        if(frozen)actions() else Row(verticalAlignment=Alignment.CenterVertically) { zoomButtons();Column(Modifier.weight(1f)) { status() } }
                    }
                }
                Column(Modifier.width(88.dp).fillMaxHeight().clip(RoundedCornerShape(20.dp)).background(Color.Black.copy(alpha=.7f)),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(20.dp,Alignment.CenterVertically)) { shutter();galleryButton() }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha=.75f)).padding(horizontal=14.dp).padding(bottom=10.dp)) {
                    Row(verticalAlignment=Alignment.CenterVertically) {
                        GlyphButton("close",tr("Закрыть камеру"),"camera.close") { close() }
                        Text(tr("Камера"),fontWeight=FontWeight.SemiBold,textAlign=TextAlign.Center,modifier=Modifier.weight(1f))
                        GlyphButton("history",tr("История переводов"),"camera.history") { open("history") }
                        GlyphButton("settings",tr("Настройки распознавания"),"camera.models") { open("ocrModels") }
                    }
                    Row(verticalAlignment=Alignment.CenterVertically,content=languages)
                }
                Spacer(Modifier.weight(1f))
                Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha=.8f)).padding(horizontal=20.dp,vertical=10.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    if(frozen)Note(tr("Разведите пальцы, чтобы увеличить снимок")) else Row(verticalAlignment=Alignment.CenterVertically) { Text(tr("Коснитесь текста для фокуса"),fontSize=11.sp,modifier=Modifier.weight(1f));zoomButtons() }
                    status()
                    if(frozen)actions()
                    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) { galleryButton();shutter();Spacer(Modifier.width(80.dp)) }
                }
            }
        }
    }
}
@Composable private fun ZoomablePicture(bitmap:android.graphics.Bitmap,blocks:List<org.openoffline.translator.inference.OcrBlock> = emptyList(),translations:List<String> = emptyList(),modifier:Modifier=Modifier) {
    var scale by remember(bitmap) { mutableFloatStateOf(1f) }
    var offset by remember(bitmap) { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    BoxWithConstraints(modifier.clip(androidx.compose.ui.graphics.RectangleShape).pointerInput(bitmap) {
        detectTapGestures(onDoubleTap={scale=if(scale>1f)1f else 2f;offset=androidx.compose.ui.geometry.Offset.Zero})
    }.pointerInput(bitmap) {
        detectTransformGestures { _,pan,zoom,_ -> scale=(scale*zoom).coerceIn(1f,5f);offset=if(scale>1f)offset+pan else androidx.compose.ui.geometry.Offset.Zero }
    },contentAlignment=Alignment.Center) {
        val ratio=bitmap.width.toFloat()/bitmap.height
        val imageWidth=minOf(maxWidth,maxHeight*ratio)
        BoxWithConstraints(Modifier.width(imageWidth).aspectRatio(ratio).graphicsLayer(scaleX=scale,scaleY=scale,translationX=offset.x,translationY=offset.y)) {
            Image(bitmap.asImageBitmap(),tr("Изображение с переводом"),modifier=Modifier.fillMaxSize())
            blocks.zip(translations).forEach { (block,text) -> Text(text,fontSize=12.sp,color=Color.Black,modifier=Modifier.offset(x=maxWidth*block.left,y=maxHeight*block.top).width((maxWidth*(block.right-block.left)).coerceAtLeast(24.dp)).background(Color.White.copy(alpha=.93f))) }
        }
    }
}
/** Compact progress while the translation grows in place, so the text stays visible. */
@Composable private fun StreamingBar(state:TranslatorState) {
    BackHandler { state.cancel() }
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing),contentAlignment=Alignment.BottomCenter) {
        Row(Modifier.padding(16.dp).widthIn(max=560.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color(0xFF2C2C2E)).padding(horizontal=16.dp,vertical=8.dp).testTag("processing.streaming"),verticalAlignment=Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(20.dp),color=KatAccent,strokeWidth=2.dp)
            Spacer(Modifier.width(12.dp))
            Text(state.status,color=Color.White,fontSize=15.sp,maxLines=1,modifier=Modifier.weight(1f).testTag("processing.status"))
            TextButton(onClick=state::cancel,modifier=Modifier.testTag("processing.cancel")) { Text(tr("Отменить"),fontSize=16.sp) }
        }
    }
}
@Composable internal fun Processing(state:TranslatorState,checkingPackages:Boolean=false) {
    BackHandler { if(!checkingPackages)state.cancel() }
    val focus=LocalFocusManager.current;val keyboard=LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) { focus.clearFocus(force=true);keyboard?.hide() }
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black).testTag("processing.overlay")) {
    val viewportHeight=maxHeight
    val preparation=checkingPackages || state.preparingModel
    Box(Modifier.matchParentSize().pointerInput(Unit) { detectTapGestures {} })
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min=viewportHeight).padding(24.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
        if(!preparation) { CircularProgressIndicator(color=KatAccent);Spacer(Modifier.height(20.dp)) }
        Text(if(checkingPackages)tr("Проверка моделей","Checking models") else state.status,color=Color.White,fontSize=20.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.testTag("processing.status"))
        if(preparation) {
            val progress=state.verificationProgress
            CatProgress(if(checkingPackages)null else progress,Modifier.padding(vertical=16.dp).testTag("models.preparation"),prominent=true)
            if(checkingPackages || progress!=null)Text(tr("Первая полная проверка моделей может занять некоторое время. При следующих запусках неизменённые файлы проверяются быстрее.","The first full model check can take a while. Unchanged files are checked faster on subsequent launches."),color=Muted,modifier=Modifier.testTag("models.firstVerificationHint"))
        }
        if(!preparation && state.segmentCount>1)LinearProgressIndicator(progress={state.segmentIndex.toFloat()/state.segmentCount},modifier=Modifier.fillMaxWidth().padding(vertical=16.dp))
        if(!checkingPackages)TextButton(onClick=state::cancel,modifier=Modifier.clip(CircleShape).background(KatAccent.copy(alpha=.12f)).testTag("processing.cancel")) { Text(tr("Отменить"),fontSize=17.sp,modifier=Modifier.padding(horizontal=16.dp)) }
    }
    }
}
