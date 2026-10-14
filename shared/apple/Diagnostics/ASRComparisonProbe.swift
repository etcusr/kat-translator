#if ASR_COMPARISON_PROBE
import ASRProbeSupport
import Foundation
import UIKit
import OfflineCore

/// Development-only comparison of fixed synthetic fixtures. No user audio/history is exported.
/// Compiled only by OT_ASR_BENCHMARK_BUILD=1; normal builds have no extra ASR dependency.
@MainActor enum ASRComparisonProbe {
    static func run(packages: PackageDownloadCoordinator, progress: (String) -> Void) async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["OT_ASR_COMPARISON"] == "1" else { return }
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdle }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let requestedEngine = env["OT_ASR_ENGINE"] ?? "parakeet"
        guard ["whisper", "parakeet", "ultra", "nemotron", "qwen"].contains(requestedEngine) else { throw PipelineError.modelLoad }
        let engine = requestedEngine
        let runID = env["OT_ASR_RUN_ID"] ?? UUID().uuidString
        let residentMT = env["OT_ASR_RESIDENT_MT"] == "1"
        let outputName = engine + (residentMT ? "-index-resident" : "")
        func report(_ text: String) {
            progress(engine + " · " + text)
            try? text.write(to: documents.appendingPathComponent("asr-comparison-status.txt"), atomically: true, encoding: .utf8)
        }
        let fixtures = ["short", "medium", "long-ru", "long-en"]
        let converter = AudioConverter()
        var clips: [(String, [Float])] = []
        for name in fixtures {
            clips.append((name, try converter.resampleAudioFile(documents.appendingPathComponent("DevelopmentFixtures/" + name + ".aiff"))))
        }
        let monitor = ResourceMonitor()
        var peakResident: UInt64 = 0, minimumHeadroom = UInt64.max
        let sampler = Task {
            while !Task.isCancelled {
                monitor.sample()
                peakResident = max(peakResident, monitor.residentMemory ?? 0)
                if let available = monitor.availableToApp { minimumHeadroom = min(minimumHeadroom, available) }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { sampler.cancel() }
        var rows: [[String: Any]] = []
        var loadSeconds = 0.0
        var mtChecks: [[String: Any]] = []
        func save(_ status: String) throws {
            let result: [String: Any] = ["engine": engine, "loadSeconds": loadSeconds, "status": status,
                "runID": runID,
                "residentMT": residentMT, "mtChecks": mtChecks,
                "rows": rows, "peakFootprint": monitor.peakFootprint, "peakResident": peakResident,
                "minimumHeadroom": minimumHeadroom, "thermalAtEnd": AppModel.thermalState,
                "system": UIDevice.current.systemVersion, "physicalMemory": ProcessInfo.processInfo.physicalMemory]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: documents.appendingPathComponent("asr-comparison-" + outputName + ".json"), options: .atomic)
        }
        let translator = LlamaTranslationBackend()
        if residentMT {
            report("loading-index")
            guard let url = packages.indexTranslation.installedURL else { throw PipelineError.modelLoad }
            try await translator.load(modelURL: url, model: .index9B)
            let result = try await translator.translate(text: "Пожалуйста, не добавляйте сахар. Мне нужен чай без сахара.", source: .russian, target: .english)
            mtChecks.append(["stage": "before", "text": result.text, "seconds": result.processingSeconds])
        }
        report("loading")
        let started = ProcessInfo.processInfo.systemUptime
        let whisper = WhisperBackend()
        let parakeet = AsrManager()
        let nemotron = StreamingNemotronMultilingualAsrManager()
        let qwen = QwenASRProbeEngine()
        if engine == "whisper" {
            guard let url = packages.whisper.installedURL else { throw PipelineError.modelLoad }
            try await whisper.load(modelURL: url)
        } else if engine == "qwen" {
            try await qwen.load(documents.appendingPathComponent("DevelopmentModels/qwen3-asr-06b"))
        } else if engine == "nemotron" {
            try await nemotron.loadModels(from: documents.appendingPathComponent("DevelopmentModels/nemotron-multilingual-2240"))
            await nemotron.setLanguage("auto")
        } else {
            let folder = engine == "ultra" ? "parakeet-ultra-coreml" : "parakeet-tdt-0.6b-v3-coreml"
            let url = documents.appendingPathComponent("DevelopmentModels/" + folder)
            let version: AsrModelVersion = engine == "ultra" ? .ultra : .v3
            let models = try await Task.detached(priority: .userInitiated) { try AsrModels.loadLocal(from: url, version: version) }.value
            try await parakeet.loadModels(models)
        }
        loadSeconds = ProcessInfo.processInfo.systemUptime - started
        try save("loaded")
        for pass in 0..<3 {
            for (name, samples) in clips {
                if pass == 0 && name != "short" { continue } // First inference is reported separately.
                guard ![.serious, .critical].contains(ProcessInfo.processInfo.thermalState) else {
                    try save("skipped-thermal"); report("skipped-thermal"); await whisper.unload(); await parakeet.cleanup(); return
                }
                report("pass \(pass) · \(name)")
                let start = ProcessInfo.processInfo.systemUptime
                let text: String
                if engine == "whisper" {
                    text = try await whisper.transcribe(CapturedAudio(samples: samples), language: nil).text
                } else if engine == "qwen" {
                    text = await qwen.transcribe(samples)
                } else if engine == "nemotron" {
                    await nemotron.reset()
                    _ = try await nemotron.process(samples: samples)
                    text = try await nemotron.finish()
                } else {
                    var state = try TdtDecoderState()
                    text = try await parakeet.transcribe(samples, decoderState: &state).text
                }
                rows.append(["fixture": name, "pass": pass, "seconds": ProcessInfo.processInfo.systemUptime - start,
                    "audioSeconds": Double(samples.count) / 16000, "text": text, "thermal": AppModel.thermalState])
                try save("running")
            }
        }
        if residentMT {
            let result = try await translator.translate(text: "Пожалуйста, не добавляйте сахар. Мне нужен чай без сахара.", source: .russian, target: .english)
            mtChecks.append(["stage": "after", "text": result.text, "seconds": result.processingSeconds])
        }
        await translator.unload(); await whisper.unload(); await parakeet.cleanup()
        await nemotron.cleanup()
        await qwen.unload()
        try save("complete"); report("complete")
    }
}
private actor QwenASRProbeEngine {
    private var model: Qwen3ASRModel?
    func load(_ url: URL) async throws {
        model = try await Qwen3ASRModel.fromPretrained(cacheDir: url, offlineMode: true)
    }
    func transcribe(_ samples: [Float]) -> String {
        model!.transcribe(audio: samples, sampleRate: 16000, language: nil, maxTokens: 768)
    }
    func unload() { model?.unload(); model = nil }
}
#endif
