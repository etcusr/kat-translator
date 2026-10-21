import Foundation
import UIKit
import AVFoundation
import OfflineCore

/// Explicit development launch only. Reads only a deliberately supplied fixture; normal recordings are never inspected.
@MainActor enum RecordingPreviewProbe {
    static func run(packages: PackageDownloadCoordinator, progress: (String) -> Void) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OT_RECORDING_PREVIEW_PROBE"] == "1" else { return }
        if let mode = environment["OT_SPEECH_CORRECTNESS_PROBE"] {
            try await DeviceSpeechCorrectnessProbe.run(packages: packages, mode: mode, progress: progress)
            return
        }
        let previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if environment["OT_PREVIEW_QUALITY_CLEANUP"] == "1" {
            for name in ["DevelopmentFixtures/quality.aiff", "recording-preview-status.txt",
                         "recording-preview-index-translate-9b-q4km-quality-hybrid-whisper-manual.json"] {
                let file = documents.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
            progress("quality-fixture-cleaned")
            return
        }
        func report(_ value: String) {
            progress(value)
            print("RecordingPreviewProbe: " + value)
            try? value.write(to: documents.appendingPathComponent("recording-preview-status.txt"), atomically: true, encoding: .utf8)
        }
        report("loading")
        let quality = environment["OT_PREVIEW_QUALITY"] == "1"
        let verify = environment["OT_PREVIEW_VERIFY"] == "1"
        let engine = environment["OT_HYBRID_ASR_ENGINE"] ?? "automatic"
        guard engine != "apple" else { throw PipelineError.recognitionUnavailable }
        let recognitionPreference = RecognitionPreference.restoredSelection(engine)
        let autoLanguage = environment["OT_HYBRID_AUTO_LANGUAGE"] == "1"
        let suffix = "-hybrid-" + engine + (autoLanguage ? "-auto" : "-manual") + (verify ? "-verified" : "")
        let requestedFixture = environment["OT_PREVIEW_FIXTURE"] ?? "short"
        let fixtureName = quality ? "quality" : (["short", "medium", "long-ru", "long-en", "thai"].contains(requestedFixture) ? requestedFixture : "short")
        guard environment["OT_PREVIEW_MODEL"] != "qwen" else { throw PipelineError.modelLoad }
        let model: TranslationModel = .index9B
        let source: SpeechLanguage = fixtureName == "thai" ? .thai : (["short", "long-ru", "quality"].contains(fixtureName) ? .russian : .english)
        let hint: SpeechLanguage? = autoLanguage ? nil : source
        let target = source.opposite
        let url = fixtureName == "thai" ? Bundle.main.url(forResource: "wayu-m_elderly_deep", withExtension: "m4a")! : documents.appendingPathComponent("DevelopmentFixtures/" + fixtureName + ".aiff")
        let mt = packages.indexTranslation
        guard let mtURL = mt.installedURL, let asrURL = packages.primaryRecognition(for: recognitionPreference) else { throw PipelineError.modelLoad }
        let playback = RecordingProbePlayback()
        let recognition = RecordingQualityASR(enabled: quality)
        let pipeline = ConversationPipeline(asr: recognition, translator: LlamaTranslationBackend(), speech: SherpaSpeechBackend(), player: playback)
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
        let modes = quality ? [environment["OT_PREVIEW_QUALITY_MODE"] == "during-recording" ? "during-recording" : "after-stop"] : (environment["OT_PREVIEW_SINGLE"] == "1" ? ["after-stop"] : (verify ? ["warmup", "during-recording-verified"] : ["warmup", "after-stop", "during-recording"]))
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
            var observations: [[String: Any]] = []
            var lastSource = ""
            let observe = Task {
                while !Task.isCancelled {
                    let source = pipeline.voiceFields.sourceText
                    if quality && !source.isEmpty && source != lastSource {
                        lastSource = source
                        observations.append(["seconds": ProcessInfo.processInfo.systemUptime - captureStart,
                            "source": source, "translation": pipeline.voiceFields.translatedText])
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            defer { observe.cancel() }
            let captured = try await AudioRecorder.replayFixture(captureURL, started: { snapshot in
                if mode.hasPrefix("during-recording") {
                    _ = pipeline.beginRecordingPreview(source: hint, target: target, speakResult: !quality, snapshot: snapshot)
                }
            }, boundary: { end, quiet in
                if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) { pipeline.suspendRecordingPreview(reason: "thermal") }
                else { pipeline.offerRecordingBoundary(end, endsInSilence: quiet) }
            })
            observe.cancel()
            report(model.title + " · " + fixtureName + " · " + mode + " · finalizing")
            let stop = ProcessInfo.processInfo.systemUptime
            let captureWallSeconds = stop - captureStart
            playback.stopTime = stop
            await pipeline.runRecording(audio: captured.0, speechEnd: captured.1, source: hint, target: target,
                speakResult: !quality, inputMode: "fixture", thermal: thermal, stoppedAt: stop,
                requestedPreview: mode.hasPrefix("during-recording"), fallbackReason: nil, verifyPreview: verify)
            if let metric = pipeline.samples.last {
                let encoded = try JSONEncoder().encode(metric)
                rows.append(["mode": mode, "requestedSource": hint?.rawValue ?? "auto", "metric": try JSONSerialization.jsonObject(with: encoded),
                    "source": pipeline.voiceFields.sourceText, "translation": pipeline.voiceFields.translatedText,
                    "recognitionPreparationSeconds": recognitionPreparationSeconds,
                    "peakFootprint": monitor.peakFootprint, "peakResident": peakResident,
                    "availableAtEnd": monitor.availableToApp ?? 0, "minimumHeadroom": minimumHeadroom,
                    "captureWallSeconds": captureWallSeconds, "previews": observations,
                    "recognitionPasses": await recognition.log.rows,
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

/// Private text evidence only in an explicitly requested fixture probe.
private actor RecordingQualityLog {
    var rows: [[String: Any]] = []
    func append(_ result: ASRResult, samples: Int) {
        guard rows.count < 200 else { return }
        rows.append(["samples": samples, "seconds": result.processingSeconds, "text": result.text,
                     "segments": result.segments.map { ["text": $0.text, "end": $0.endSample] as [String: Any] }])
    }
}
private final class RecordingQualityASR: ASRBackend, @unchecked Sendable {
    private let base = RoutedASRBackend()
    private let enabled: Bool
    let log = RecordingQualityLog()
    init(enabled: Bool) { self.enabled = enabled }
    func load(modelURL: URL) async throws { try await base.load(modelURL: modelURL) }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        let result = try await base.transcribe(audio, language: language)
        if enabled { await log.append(result, samples: audio.samples.count) }
        return result
    }
    func cancel() { base.cancel() }
    func unload() async { await base.unload() }
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

/// Opt-in synthetic checks through the production pipeline, voice and iPhone player.
/// No microphone, history, saved settings or user-provided text are used.
@MainActor private enum DeviceSpeechCorrectnessProbe {
    static func run(packages: PackageDownloadCoordinator, mode: String, progress: (String) -> Void) async throws {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeechCorrectnessProbe")
        if mode == "cleanup" {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            progress("speech-check-cleaned"); return
        }
        guard mode == "1", let voice = packages.selectedVoiceDirectories[.russian],
              let model = packages.indexTranslation.installedURL else { throw PipelineError.modelLoad }
        let oldIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = oldIdle }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        func save(_ status: String) throws {
            progress(status)
            let result: [String: Any] = ["status": status, "voice": packages.selectedVoiceModelIDs[.russian] ?? "unknown", "rows": rows]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appendingPathComponent("results.json"), options: .atomic)
        }
        let first = "Пожалуйста, подтвердите, что в стоимость номера входит завтрак для каждого гостя и что из окна открывается красивый вид на город."
        let second = "Встречаемся на 1-й улице перед 1-м рейсом."
        let full = first + "\n\t" + second + "  Измените дату с 15-го на 16-е октября. Вспомним 80-е годы."
        let input = "The hotel opens at eight in the morning. Breakfast is included in the price. Please leave the keys at reception. The museum is near the railway station. The bus leaves every twenty minutes. We will meet at the entrance tomorrow."
        for name in ["controlled", "real-index"] {
            try save("running-" + name)
            let events = DeviceSpeechEvents()
            let speech = DeviceObservedSpeech()
            let player = DeviceObservedPlayer(events: events)
            let translator = DeviceSpeechTranslation(events: events, fixture: name == "controlled" ? full : nil,
                partial: first + "\n\t" + second + "  Измените")
            let pipeline = ConversationPipeline(asr: DeviceUnusedASR(), translator: translator, speech: speech, player: player)
            await pipeline.prepare(PipelineFiles(asr: nil, translation: model, voices: [.russian: voice]), memorySaving: false)
            await pipeline.run(audio: nil, text: input, source: .english, target: .russian,
                               speakResult: true, inputMode: "text", thermal: AppModel.thermalState)
            let inputs = await speech.inputs
            let order = await events.values
            let expected = pipeline.translatedText
            func words(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            let wordsOnce = !expected.isEmpty && words(inputs.joined(separator: " ")) == words(expected)
            let early = (order.firstIndex(of: "play") ?? Int.max) < (order.firstIndex(of: "translation-finished") ?? 0)
            let completed = !player.playbacks.isEmpty && player.playbacks.count == order.filter { $0 == "play" }.count
            let expanded = inputs.map(RussianSpeechText.expandOrdinals).joined(separator: " ")
            let ordinals = name != "controlled" || ["на первой улице", "перед первым рейсом",
                "с пятнадцатого на шестнадцатое октября", "восьмидесятые годы"].allSatisfy { expanded.contains($0) }
            let valid = !player.samples.isEmpty && player.samples.allSatisfy(\.isFinite)
                && (player.samples.map { abs($0) }.max() ?? 0) > 0.05
            let passed = pipeline.error == nil && wordsOnce && early && completed && ordinals && valid
            var row: [String: Any] = ["case": name, "passed": passed, "wordsOnce": wordsOnce,
                "speechBeforeTranslationFinished": early, "playbackCompleted": completed, "ordinalsCorrect": ordinals,
                "synthesisParts": inputs.count, "playbacks": player.playbacks, "sampleRate": player.sampleRate,
                "pcmSeconds": Double(player.samples.count) / Double(max(1, player.sampleRate)),
                "outputVolume": AVAudioSession.sharedInstance().outputVolume,
                "outputRoutes": AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue },
                "translation": expected, "synthesisInputs": inputs, "expandedSpeech": expanded]
            if let error = pipeline.error { row["error"] = String(describing: error) }
            rows.append(row)
            if valid { try player.write(to: root.appendingPathComponent(name + ".wav")) }
            await pipeline.unload()
            try save(passed ? "passed-" + name : "failed-" + name)
            guard passed else { throw PipelineError.inference }
        }
        try save("complete")
    }
}

private actor DeviceSpeechEvents {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
    var playCount: Int { values.filter { $0 == "play" }.count }
}
private actor DeviceUnusedASR: ASRBackend {
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult { throw PipelineError.inference }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor DeviceSpeechTranslation: TranslationBackend {
    let events: DeviceSpeechEvents
    let fixture: String?, partialText: String
    let backend = RoutedTranslationBackend()
    init(events: DeviceSpeechEvents, fixture: String?, partial: String) {
        self.events = events; self.fixture = fixture; partialText = partial
    }
    func load(modelURL: URL) async throws {
        if fixture == nil { try await backend.load(modelURL: modelURL, model: .index9B) }
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await translate(text: text, source: source, target: target, progress: { _ in }, partial: { _ in })
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        let result: TranslationResult
        if let fixture {
            partial(partialText)
            let start = ProcessInfo.processInfo.systemUptime
            while await events.playCount < 2 {
                guard ProcessInfo.processInfo.systemUptime - start < 60 else { throw PipelineError.inference }
                try await Task.sleep(for: .milliseconds(10))
            }
            result = TranslationResult(text: fixture, firstTokenSeconds: 0, processingSeconds: 0, fragments: 1)
        } else {
            result = try await backend.translate(text: text, source: source, target: target, progress: progress, partial: partial)
        }
        await events.add("translation-finished")
        return result
    }
    nonisolated func cancel() { backend.cancel() }
    func unload() async { await backend.unload() }
}
private actor DeviceObservedSpeech: SpeechSynthesisBackend {
    let backend = SherpaSpeechBackend()
    private(set) var inputs: [String] = []
    func load(directory: URL, language: SpeechLanguage) async throws { try await backend.load(directory: directory, language: language) }
    func synthesize(text: String) async throws -> SpeechPCM { inputs.append(text); return try await backend.synthesize(text: text) }
    nonisolated func cancel() { backend.cancel() }
    func unload() async { await backend.unload() }
}
@MainActor private final class DeviceObservedPlayer: SpeechPlayback {
    let player = SpeechPlayer(), events: DeviceSpeechEvents
    var samples: [Float] = [], sampleRate = 0
    var playbacks: [[String: Double]] = []
    init(events: DeviceSpeechEvents) { self.events = events }
    func play(_ pcm: SpeechPCM) async throws {
        guard sampleRate == 0 || sampleRate == pcm.sampleRate else { throw PipelineError.invalidAudio }
        sampleRate = pcm.sampleRate; samples += pcm.samples
        await events.add("play")
        let start = ProcessInfo.processInfo.systemUptime
        try await player.play(pcm)
        playbacks.append(["wallSeconds": ProcessInfo.processInfo.systemUptime - start,
                          "pcmSeconds": Double(pcm.samples.count) / Double(pcm.sampleRate)])
    }
    func play(file: URL) async throws { throw PipelineError.invalidAudio }
    func stop() { player.stop() }
    func pause() { player.pause() }
    func resume() { player.resume() }
    func setRate(_ rate: Float) { player.setRate(rate) }
    func write(to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw PipelineError.invalidAudio }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }
}
