import SwiftUI
import OfflineCore

/// A single focal point for recording and processing on both platforms.
struct VoiceStageControls: View {
    @AppStorage("showTechnicalInfo") private var showTechnicalInfo = false
    @ObservedObject var model: AppModel
    @ObservedObject private var session: ConversationPipeline
    @ObservedObject private var recorder: AudioRecorder
    @ObservedObject private var packages: PackageDownloadCoordinator
    let recordingMode: RecordingMode
    let status: String
    let showWizard: Bool
    let compact: Bool
    let availableSize: CGSize
    let showModels: () -> Void
    let importAudio: () -> Void

    init(model: AppModel, recordingMode: RecordingMode, status: String, showWizard: Bool, compact: Bool, availableSize: CGSize, showModels: @escaping () -> Void, importAudio: @escaping () -> Void) {
        self.model = model; session = model.session; recorder = model.recorder; packages = model.packages
        self.recordingMode = recordingMode; self.status = status; self.showWizard = showWizard
        self.compact = compact; self.availableSize = availableSize; self.showModels = showModels; self.importAudio = importAudio
    }
    private var busy: Bool {
        session.isBusy || recorder.isRecording || recorder.starting || model.preparingRecording || model.importingAudio || model.finishing || model.changingTranslation
    }
    private var canPause: Bool {
        (recorder.isRecording && !model.finishing) || (session.isSpeaking && !showWizard)
    }
    private var actionDiameter: CGFloat {
        if compact { return 64 }
        #if os(macOS)
        // Use the viewport, not this control's measured size, to avoid a layout feedback loop.
        return min(144, max(80, min(availableSize.width / 1440, availableSize.height / 1000) * 144))
        #else
        return 144
        #endif
    }
    private var actionSpacing: CGFloat {
        #if os(macOS)
        max(16, actionDiameter / 6)
        #else
        24
        #endif
    }
    private var stageHeight: CGFloat {
        #if os(macOS)
        compact ? 64 : (showWizard ? 184 : actionDiameter + 40)
        #else
        compact ? 64 : 184
        #endif
    }
    private var stageWidth: CGFloat {
        #if os(macOS)
        showWizard ? 216 : (busy ? actionDiameter * 1.5 : actionDiameter)
        #else
        216
        #endif
    }
    var body: some View {
        VStack(spacing: 16) {
            if !packages.restored || (!session.isReady && busy) || session.isPreparingRecognition {
                ModelPreparationView(checking: !packages.restored,
                    status: !packages.restored ? L10n.text("Проверяю модели…") : status,
                    canCancel: session.isBusy || model.importingAudio, cancel: model.cancel)
            } else if !packages.ready {
                Button(L10n.text("Скачать модели для перевода"), action: showModels)
                    .katPrimaryAction().foregroundStyle(.black).fontWeight(.semibold)
            } else if !session.isReady || (!model.isVoiceReady && !busy) {
                Button(prepareTitle) { Task { await model.load(resultMode: .voice) } }
                    .katPrimaryAction().foregroundStyle(.black).fontWeight(.semibold).disabled(busy)
                    .accessibilityIdentifier("voice.prepare")
            } else {
                HStack(spacing: actionSpacing) {
                    #if os(macOS)
                    if !busy { audioImportButton }
                    #endif
                ZStack {
                    RecordButton(mode: recordingMode, enabled: !busy && model.isVoiceReady && model.voiceLanguageIssue == nil,
                                 recording: recorder.isRecording, starting: recorder.starting || model.preparingRecording,
                                 processing: session.isBusy && !recorder.isRecording || model.finishing || model.importingAudio,
                                 paused: recorder.isPaused, speaking: session.isSpeaking,
                                 diameter: actionDiameter, stopSpeech: { model.cancel() },
                                 start: { Task { await model.beginRecording() } }, stop: { Task { await model.finishRecording() } })
                        .accessibilityIdentifier("voice.record")
                        .help(recordingMode == .hold ? L10n.text("Удерживайте и говорите") : L10n.text("Нажмите для записи"))
                }.frame(width: stageWidth, height: stageHeight)
                    .overlay(alignment: .trailing) {
                        if canPause {
                            Button {
                                if recorder.isRecording { recorder.togglePause() } else { session.toggleSpeechPause() }
                            } label: {
                                Image(systemName: (recorder.isRecording ? recorder.isPaused : session.isSpeechPaused) ? "play.fill" : "pause.fill")
                                    .font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                                    .background(.white.opacity(0.07), in: Circle())
                            }.buttonStyle(.plain).foregroundStyle(KatTheme.accent)
                                .accessibilityIdentifier("voice.pauseResume")
                                .accessibilityLabel(recorder.isRecording
                                    ? (recorder.isPaused ? L10n.text("Продолжить запись") : L10n.text("Приостановить запись"))
                                    : (session.isSpeechPaused ? L10n.text("Продолжить озвучку") : L10n.text("Приостановить озвучку")))
                                .offset(x: 36)
                        }
                    }
                }
                #if os(iOS)
                if showTechnicalInfo && !busy {
                    Button(action: importAudio) {
                        Label(L10n.text("Открыть аудиофайл"), systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.voiceLanguageIssue != nil)
                    .accessibilityIdentifier("voice.import")
                }
                #endif
                if busy {
                    VStack(spacing: 8) {
                        Text(status).font(.system(size: 17, weight: .medium))
                            .accessibilityIdentifier("voice.processing.status")
                        if recorder.isRecording && !model.finishing {
                            Text(String(format: "%d:%02d / %d:00", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60, recorder.limitSeconds / 60))
                                .font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
                                .accessibilityIdentifier("voice.recording.time")
                        }
                        if showWizard, let progress = session.translationProgress {
                            Text(L10n.text("Перевожу часть \(min(progress.completedParts + 1, progress.totalParts)) из \(progress.totalParts)"))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if (!recorder.isRecording || model.finishing) && (!session.isSpeaking || showWizard) { cancelButton }
                    }
                }
            }
        }.multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, compact ? 8 : 32)
    }
    #if os(macOS)
    private var audioImportButton: some View {
        Button(action: importAudio) {
            ZStack {
                Circle().fill(KatTheme.accent.opacity(0.12))
                Circle().stroke(KatTheme.accent, lineWidth: 2).padding(max(4, actionDiameter / 18))
                Image(systemName: "paperclip")
                    .font(.system(size: actionDiameter * 0.32))
                    .foregroundStyle(KatTheme.accent)
            }.frame(width: actionDiameter, height: actionDiameter).contentShape(Circle())
        }.buttonStyle(.plain)
            .disabled(model.voiceLanguageIssue != nil)
            .accessibilityLabel(L10n.text("Открыть аудиофайл"))
            .accessibilityIdentifier("voice.import")
            .help(L10n.text("Открыть аудиофайл"))
    }
    #endif
    private var cancelButton: some View {
        Button(L10n.text("Отменить"), role: .cancel) { model.cancel() }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("voice.cancel")
    }
    private var prepareTitle: String {
        #if os(iOS)
        L10n.text("Перевести")
        #else
        L10n.text("Подготовить перевод")
        #endif
    }
}
