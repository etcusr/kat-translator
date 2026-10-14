import Foundation
import UIKit
import OfflineCore

/// Explicit development launch only. Fixed synthetic fixtures; never exports user text.
@MainActor enum RecordingPreviewProbe {
    static func run(packages: PackageDownloadCoordinator, progress: (String) -> Void) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OT_RECORDING_PREVIEW_PROBE"] == "1" else { return }
        let previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func report(_ value: String) {
            progress(value)
            print("RecordingPreviewProbe: " + value)
            try? value.write(to: documents.appendingPathComponent("recording-preview-status.txt"), atomically: true, encoding: .utf8)
        }
        report("loading")
        let verify = environment["OT_PREVIEW_VERIFY"] == "1"
        let engine = environment["OT_HYBRID_ASR_ENGINE"] ?? "automatic"
        guard engine != "apple" else { throw PipelineError.recognitionUnavailable }
        let recognitionPreference = RecognitionPreference.restoredSelection(engine)
        let autoLanguage = environment["OT_HYBRID_AUTO_LANGUAGE"] == "1"
        let suffix = "-hybrid-" + engine + (autoLanguage ? "-auto" : "-manual") + (verify ? "-verified" : "")
        let requestedFixture = environment["OT_PREVIEW_FIXTURE"] ?? "short"
        let fixtureName = ["short", "medium", "long-ru", "long-en", "thai"].contains(requestedFixture) ? requestedFixture : "short"
        guard environment["OT_PREVIEW_MODEL"] != "qwen" else { throw PipelineError.modelLoad }
        let model: TranslationModel = .index9B
        let source: SpeechLanguage = fixtureName == "thai" ? .thai : (["short", "long-ru"].contains(fixtureName) ? .russian : .english)
        let hint: SpeechLanguage? = autoLanguage ? nil : source
        let target = source.opposite
        let url = fixtureName == "thai" ? Bundle.main.url(forResource: "wayu-m_elderly_deep", withExtension: "m4a")! : documents.appendingPathComponent("DevelopmentFixtures/" + fixtureName + ".aiff")
        let mt = packages.indexTranslation
        guard let mtURL = mt.installedURL, let asrURL = packages.primaryRecognition(for: recognitionPreference) else { throw PipelineError.modelLoad }
        let playback = RecordingProbePlayback()
        let pipeline = ConversationPipeline(asr: RoutedASRBackend(), translator: LlamaTranslationBackend(), speech: SherpaSpeechBackend(), player: playback)
        await pipeline.prepare(PipelineFiles(asr: asrURL, translation: mtURL, voices: packages.selectedVoiceDirectories,
            voiceModelIDs: packages.selectedVoiceModelIDs, translationModel: model, omnilingual: packages.omnilingualDirectory, ultra: packages.recognition.ultra,
            recognitionPreference: recognitionPreference), memorySaving: false, recognitionLanguage: hint)
        guard pipeline.isReady else { throw PipelineError.modelLoad }
        let recognitionStart = ProcessInfo.processInfo.systemUptime
        await pipeline.preloadRecognition(source: hint)
        let recognitionPreparationSeconds = ProcessInfo.processInfo.systemUptime - recognitionStart
        guard pipeline.error == nil else { throw PipelineError.modelLoad }
        var rows: [[String: Any]] = []
        let monitor = ResourceMonitor()
        var peakResident: UInt64 = 0, minimumHeadroom = UInt64.max
        let sampling = Task {
            while !Task.isCancelled {
                monitor.sample(); peakResident = max(peakResident, monitor.residentMemory ?? 0)
                if let available = monitor.availableToApp { minimumHeadroom = min(minimumHeadroom, available) }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { sampling.cancel() }
        // Unmeasured same-fixture warmup establishes ASR/MT/voice residency for both A/B runs.
        let modes = environment["OT_PREVIEW_SINGLE"] == "1" ? ["after-stop"] : (verify ? ["warmup", "during-recording-verified"] : ["warmup", "after-stop", "during-recording"])
        for mode in modes {
            try Task.checkCancellation()
            if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
                rows.append(["mode": mode, "status": "skipped-thermal"]); break
            }
            report(model.title + " · " + fixtureName + " · " + mode)
            monitor.reset(); peakResident = 0; minimumHeadroom = UInt64.max; playback.resetMeasurements()
            let thermal = AppModel.thermalState
            let warmupURL = documents.appendingPathComponent("DevelopmentFixtures/warmup-" + source.rawValue + ".aiff")
            let captureURL = mode == "warmup" && fixtureName.hasPrefix("long-") ? warmupURL : url
            let captureStart = ProcessInfo.processInfo.systemUptime
            let captured = try await AudioRecorder.replayFixture(captureURL, started: { snapshot in
                if mode.hasPrefix("during-recording") {
                    _ = pipeline.beginRecordingPreview(source: hint, target: target, speakResult: true, snapshot: snapshot)
                }
            }, boundary: { end in
                if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) { pipeline.suspendRecordingPreview(reason: "thermal") }
                else { pipeline.offerRecordingBoundary(end) }
            })
            report(model.title + " · " + fixtureName + " · " + mode + " · finalizing")
            let stop = ProcessInfo.processInfo.systemUptime
            let captureWallSeconds = stop - captureStart
            playback.stopTime = stop
            await pipeline.runRecording(audio: captured.0, speechEnd: captured.1, source: hint, target: target,
                speakResult: true, inputMode: "fixture", thermal: thermal, stoppedAt: stop,
                requestedPreview: mode.hasPrefix("during-recording"), fallbackReason: nil, verifyPreview: verify)
            if let metric = pipeline.samples.last {
                let encoded = try JSONEncoder().encode(metric)
                rows.append(["mode": mode, "requestedSource": hint?.rawValue ?? "auto", "metric": try JSONSerialization.jsonObject(with: encoded),
                    "source": pipeline.voiceFields.sourceText, "translation": pipeline.voiceFields.translatedText,
                    "recognitionPreparationSeconds": recognitionPreparationSeconds,
                    "peakFootprint": monitor.peakFootprint, "peakResident": peakResident,
                    "availableAtEnd": monitor.availableToApp ?? 0, "minimumHeadroom": minimumHeadroom,
                    "captureWallSeconds": captureWallSeconds,
                    "playbackEvents": playback.events, "maximumPlaybackGapSeconds": playback.maximumGap,
                    "thermalAtEnd": AppModel.thermalState])
            }
            // Persist after each bounded run in case the user closes the development launch.
            let output = documents.appendingPathComponent("recording-preview-" + model.rawValue + "-" + fixtureName + suffix + ".json")
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        let output = documents.appendingPathComponent("recording-preview-" + model.rawValue + "-" + fixtureName + suffix + ".json")
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        await pipeline.unload()
        report("complete")
    }
}

/// Measures actual play() calls/completions, not acoustic output. Development probe only.
@MainActor private final class RecordingProbePlayback: SpeechPlayback {
    private let player = SpeechPlayer()
    func play(file: URL) async throws { try await player.play(file: file) }
    var stopTime = 0.0
    private(set) var events: [[String: Double]] = []
    private(set) var maximumGap = 0.0
    private var previousCompletion: Double?
    func resetMeasurements() { events = []; maximumGap = 0; previousCompletion = nil }
    func play(_ pcm: SpeechPCM) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        if let previousCompletion { maximumGap = max(maximumGap, started - previousCompletion) }
        try await player.play(pcm)
        let finished = ProcessInfo.processInfo.systemUptime
        previousCompletion = finished
        events.append(["startSinceStop": started - stopTime, "endSinceStop": finished - stopTime,
                       "pcmSeconds": Double(pcm.samples.count) / Double(pcm.sampleRate)])
    }
    func stop() { player.stop() }
    func pause() { player.pause() }
    func resume() { player.resume() }
    func setRate(_ rate: Float) { player.setRate(rate) }
}
