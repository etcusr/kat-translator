import Foundation
import Combine

struct CapturedAudio { var durationSeconds: Double = 10 }
enum SpeechLanguage { case english }
enum Mode { case voice }
struct RecordingStopTrace { static func mark(_ value: String) {} }
struct L10n { static func text(_ value: String) -> String { value } }
final class DownloadBackgroundWork { func end() {} }
@MainActor enum AppPlatform { static var isActive = true }
@MainActor final class Recorder {
    var isRecording = true, starting = false, finalSpeechEnd = 1
    var gate: CheckedContinuation<Void, Never>?
    func stop() async throws -> CapturedAudio {
        isRecording = false
        await withCheckedContinuation { gate = $0 }
        return CapturedAudio()
    }
    func drain() { gate?.resume(); gate = nil }
    func cancel() { isRecording = false }
}
@MainActor final class Session {
    @Published var isBusy = false
    var isRecordingPreview = false, runs = 0
    // Cancellation completion is controlled independently of capture completion.
    func cancel() {}
    func runRecording(audio: CapturedAudio, speechEnd: Int, source: SpeechLanguage?, target: SpeechLanguage,
                      speakResult: Bool, inputMode: String, thermal: String, stoppedAt: Double,
                      requestedPreview: Bool, fallbackReason: String?, verifyPreview: Bool) async { runs += 1 }
    func finishRecordingTelemetry(footprint: UInt64, resident: UInt64, thermal: String) {}
}
@MainActor final class History {
    func applyRecordingSettings() async {}
    func refresh() async {}
    func stopPlayback() {}
}
@MainActor final class Control { func cancel() {}; func stop() {} }
@MainActor final class Model {
    var isShuttingDown = false, finishing = false, importingAudio = false, usingCamera = false
    var recorder = Recorder(), session = Session(), history = History(), recordingStart = Control(), voicePreview = Control()
    var interactionID = 0
    var inputMode: Mode = .voice
    var capturedLanguage: SpeechLanguage? = .english, capturedTarget: SpeechLanguage = .english
    var capturedAutomaticSpeech = false, capturedPreview = true, capturedVerification = false
    var capturedMode = "toggle", previewFallback: String?, message: String?
    var recordingResources: Task<Void, Never>?, audioFileTask: Task<Void, Never>?
    var peakRecordingFootprint: UInt64 = 0, peakRecordingResident: UInt64 = 0
    var deferredRecordingRetry: AnyCancellable?
    static let thermalState = "nominal"
    var pending: Bool { deferredRecording != nil }
    func interruptionBegan() { recordingInterrupted = true }
    func interruptionEnded() async { recordingInterrupted = false; await processDeferredRecording() }
    func becameActive() { recordingBecameActive() }
    init() { // OBSERVE
    }
    func refreshVoiceFiles() async {}
    func synchronizeRecognition() async {}
    // PRODUCTION_METHODS
}
@main struct Main {
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }
    @MainActor static func main() async {
        var failures = [String]()
        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures.append(label); print("FAIL: \(label)") }
        }
        let quick = Model()
        let stop = Task { await quick.finishRecording(deferProcessing: true) }
        while quick.recorder.gate == nil { await Task.yield() }
        await quick.processDeferredRecording()
        quick.recorder.drain(); await stop.value; await settle()
        expect(!quick.pending && quick.session.runs == 1, "foreground before stop drains must retry exactly once")

        let interrupted = Model()
        let interruption = Task { await interrupted.finishRecording(deferProcessing: true) }
        while interrupted.recorder.gate == nil { await Task.yield() }
        AppPlatform.isActive = false; interrupted.background()
        interrupted.recorder.drain(); await interruption.value; await settle()
        expect(interrupted.pending && interrupted.interactionID == 0, "background during interruption stop must preserve audio")
        expect(interrupted.session.runs == 0, "do not process deferred audio while backgrounded")
        AppPlatform.isActive = true; await interrupted.processDeferredRecording(); await settle()
        expect(!interrupted.pending && interrupted.session.runs == 1, "interrupted recording processes on return")

        AppPlatform.isActive = false
        let draining = Model()
        let delayed = Task { await draining.finishRecording(deferProcessing: true) }
        while draining.recorder.gate == nil { await Task.yield() }
        draining.recorder.drain(); await delayed.value; await settle()
        draining.session.isBusy = true
        AppPlatform.isActive = true; await draining.processDeferredRecording()
        draining.session.isBusy = false; await settle()
        expect(!draining.pending && draining.session.runs == 1, "preview cancellation completion must retry")
        await draining.processDeferredRecording(); await settle()
        expect(draining.session.runs == 1, "repeated activation must not duplicate processing")

        AppPlatform.isActive = false
        let inactive = Model()
        let paused = Task { await inactive.finishRecording(deferProcessing: true) }
        while inactive.recorder.gate == nil { await Task.yield() }
        inactive.recorder.drain(); await paused.value
        await inactive.processDeferredRecording(); await settle()
        expect(inactive.pending && inactive.session.runs == 0, "processing entry point rejects inactive app")
        AppPlatform.isActive = true

        let manual = Model()
        let manualStop = Task { await manual.finishRecording() }
        while manual.recorder.gate == nil { await Task.yield() }
        AppPlatform.isActive = false; manual.background()
        manual.recorder.drain(); await manualStop.value; await settle()
        expect(manual.pending && manual.session.runs == 0, "manual stop draining in background must defer")
        AppPlatform.isActive = true; await manual.processDeferredRecording(); await settle()
        expect(!manual.pending && manual.session.runs == 1, "manual stopped recording processes on return")

        let normal = Model()
        let normalStop = Task { await normal.finishRecording() }
        while normal.recorder.gate == nil { await Task.yield() }
        normal.recorder.drain(); await normalStop.value; await settle()
        expect(!normal.pending && normal.session.runs == 1, "ordinary stop still processes exactly once")

        let siri = Model()
        siri.interruptionBegan()
        let siriStop = Task { await siri.finishRecording(deferProcessing: true) }
        while siri.recorder.gate == nil { await Task.yield() }
        siri.recorder.drain(); await siriStop.value; await settle()
        expect(siri.pending && siri.session.runs == 0, "active app must still wait for audio interruption to end")
        await siri.interruptionEnded(); await settle()
        expect(!siri.pending && siri.session.runs == 1, "interruption end releases deferred processing")

        let suspended = Model()
        suspended.interruptionBegan()
        let suspendedStop = Task { await suspended.finishRecording(deferProcessing: true) }
        while suspended.recorder.gate == nil { await Task.yield() }
        AppPlatform.isActive = false; suspended.background()
        suspended.recorder.drain(); await suspendedStop.value; await settle()
        expect(suspended.pending && suspended.session.runs == 0, "suspended interrupted audio remains pending")
        // No interruption-ended notification: UIKit foreground activation must recover it.
        AppPlatform.isActive = true; suspended.becameActive(); await settle()
        expect(!suspended.pending && suspended.session.runs == 1, "foreground recovers when interruption-ended is missing")

        let earlyActivation = Model()
        earlyActivation.interruptionBegan()
        let earlyStop = Task { await earlyActivation.finishRecording(deferProcessing: true) }
        while earlyActivation.recorder.gate == nil { await Task.yield() }
        earlyActivation.becameActive(); await settle()
        earlyActivation.recorder.drain(); await earlyStop.value; await settle()
        expect(!earlyActivation.pending && earlyActivation.session.runs == 1, "activation before stop completion clears stale interruption")
        if failures.isEmpty { print("PASS: recording lifecycle") } else { exit(1) }
    }
}
