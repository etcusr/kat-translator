import SwiftUI
import WhisperKit
import OfflineCore
import CryptoKit

@main struct LabApp: App {
    @StateObject private var model = Lab()
    var body: some Scene { WindowGroup { VStack(spacing: 20) { Text("WhisperKit · file replay").font(.title2); Text(model.status); Text("Separate research app. No microphone. No final full-recording verification.").font(.caption) }.padding().task { await model.run() } } }
}

@MainActor final class Lab: ObservableObject {
    @Published var status = "Idle"
    private var didRun = false
    private var rows: [[String: Any]] = []
    private var queue: [String] = []
    private var translations: [[String: Any]] = []
    private var translatedSource = ""
    private var worker: Task<Void, Never>?
    private var failure: Error?
    private let mt = LlamaTranslationBackend()
    private var started = 0.0
    private var result: [String: Any] = [:]
    private var doc: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var runName: String { ProcessInfo.processInfo.environment["LAB_RUN"] ?? "run-a" }
    private func now() -> Double { ProcessInfo.processInfo.systemUptime }
    private func report(_ text: String) { status = text; print("LAB " + text); try? text.write(to: doc.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8) }
    private func save() {
        result["events"] = rows; result["translations"] = translations
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: doc.appendingPathComponent(runName + ".json"), options: .atomic)
    }
    private func observe(_ state: AudioStreamTranscriber.State) {
        let text = state.confirmedSegments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = rows.last?["confirmed"] as? String ?? ""
        let draft = state.unconfirmedSegments.map(\.text).joined() + state.currentText
        if text != previous || (rows.isEmpty && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.contains("Waiting for speech")) {
            rows.append(["seconds": now()-started,"confirmed":text,"draft":draft,"confirmedEnd":state.lastConfirmedSegmentEndSeconds]);save()
        }
        if result["firstDraftSeconds"] == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.contains("Waiting for speech") { result["firstDraftSeconds"] = now()-started }
        if result["firstConfirmedSeconds"] == nil && !text.isEmpty { result["firstConfirmedSeconds"] = now()-started }
        offer(text, final: false)
    }
    /// Translate only complete sentences within the already confirmed prefix; never revise it.
    private func offer(_ source: String, final: Bool) {
        guard source.hasPrefix(translatedSource) else { failure = NSError(domain:"Lab",code:3,userInfo:[NSLocalizedDescriptionKey:"Confirmed prefix was revised"]); return }
        var eligible = source
        if !final {
            guard let end = source.lastIndex(where: { ".!?".contains($0) }) else { return }
            eligible = String(source[...end])
        }
        guard eligible.count > translatedSource.count else { return }
        let addition = String(eligible.dropFirst(translatedSource.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        translatedSource = eligible;queue.append(addition)
        if worker == nil { worker = Task { await self.drain() } }
    }
    private func drain() async {
        while !queue.isEmpty && failure == nil {
            let text = queue.removeFirst(), start = now()
            do {
                let output = try await mt.translate(text:text,source:.russian,target:.english)
                translations.append(["source":text,"translation":output.text,"startedSeconds":start-started,"finishedSeconds":now()-started,"processingSeconds":output.processingSeconds])
                save()
            } catch { failure = error }
        }
        worker = nil
    }
    func run() async {
        guard !didRun else { return };didRun=true
        guard ProcessInfo.processInfo.environment["LAB_RUN"] != nil else { report("Ready; explicit lab launch required"); return }
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1) // Match the shipping Index runtime memory policy.
        UIApplication.shared.isIdleTimerDisabled=true
        defer { UIApplication.shared.isIdleTimerDisabled=false }
        var kit: WhisperKit?
        do {
            let bytes=try Data(contentsOf:doc.appendingPathComponent("full.f32"))
            let samples=bytes.withUnsafeBytes { Array($0.bindMemory(to:Float.self)) }
            result=["status":"preparing","inputSHA256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),"sampleCount":samples.count,"audioSeconds":Double(samples.count)/16000,"fullVerification":false,"speechPlayback":false,"mode":"file-replay-realtime","confirmationSegments":2,"useVAD":true,"metalNoResidency":ProcessInfo.processInfo.environment["GGML_METAL_NO_RESIDENCY"] ?? "unset"]
            let audio=ReplayAudio();report("Loading WhisperKit")
            let loadStart=now()
            let whisper=try await WhisperKit(WhisperKitConfig(modelFolder:doc.appendingPathComponent("models/openai_whisper-large-v3-v20240930_626MB").path,tokenizerFolder:doc.appendingPathComponent("tokenizer"),audioProcessor:audio,verbose:false,prewarm:true,load:true,download:false))
            kit=whisper;result["asrLoadSeconds"]=now()-loadStart
            report("Loading Index MTP2");let mtStart=now()
            try await mt.load(modelURL:doc.appendingPathComponent("index.gguf"));result["mtLoadSeconds"]=now()-mtStart
            // Do not mix cold Core ML specialization and loading with the measured replay.
            report("Cooling after preparation")
            var stable=0
            for _ in 0..<420 {
                try await Task.sleep(nanoseconds:1_000_000_000)
                stable = ProcessInfo.processInfo.thermalState == .nominal ? stable+1 : 0
                if stable>=30 { break }
            }
            guard stable>=30 else { throw NSError(domain:"Lab",code:1,userInfo:[NSLocalizedDescriptionKey:"Thermal state did not return to nominal"]) }
            let options=DecodingOptions(language:"ru",temperature:0,detectLanguage:false,skipSpecialTokens:true,withoutTimestamps:false,concurrentWorkerCount:1)
            let stream=AudioStreamTranscriber(audioEncoder:whisper.audioEncoder,featureExtractor:whisper.featureExtractor,segmentSeeker:whisper.segmentSeeker,textDecoder:whisper.textDecoder,tokenizer:whisper.tokenizer!,audioProcessor:audio,decodingOptions:options,stateChangeCallback:nil)
            let monitor=ResourceMonitor();monitor.reset();var thermalMax=0
            let monitoring=Task { while !Task.isCancelled { monitor.sample();thermalMax=max(thermalMax,ProcessInfo.processInfo.thermalState.rawValue);try? await Task.sleep(nanoseconds:250_000_000) } }
            defer { monitoring.cancel() }
            result["thermalStart"]=ProcessInfo.processInfo.thermalState.rawValue
            report("Replaying 71-second recording");started=now()
            let streaming=Task { try await stream.labStartFileReplay() }
            // Exact 100 ms PCM frames, delivered at recording speed, with absolute deadlines.
            var offset=0
            while offset<samples.count {
                let end=min(offset+1600,samples.count),deadline=started+Double(end)/16000
                let delay=deadline-now();if delay>0 { try await Task.sleep(nanoseconds:UInt64(delay*1e9)) }
                audio.append(Array(samples[offset..<end]));offset=end
                observe(await stream.labSnapshot())
                if ProcessInfo.processInfo.thermalState.rawValue>=2 {
                    await stream.stopStreamTranscription();try await streaming.value
                    throw NSError(domain:"Lab",code:2,userInfo:[NSLocalizedDescriptionKey:"Stopped at serious thermal state"])
                }
                if let failure { await stream.stopStreamTranscription();try await streaming.value;throw failure }
            }
            let stopped=now();result["captureWallSeconds"]=stopped-started
            report("Finalizing unpublished tail only")
            await stream.stopStreamTranscription();try await streaming.value
            let state=await stream.labSnapshot();observe(state)
            result["streamPasses"]=await stream.labPasses
            let confirmed=state.confirmedSegments.map(\.text).joined().trimmingCharacters(in:.whitespacesAndNewlines)
            var tailOptions=options;tailOptions.clipTimestamps=[state.lastConfirmedSegmentEndSeconds]
            let tailStart=now()
            let tail=try await whisper.transcribe(audioArray:samples,decodeOptions:tailOptions)
            let tailText=tail.map(\.text).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines)
            result["tailASRSeconds"]=now()-tailStart;result["tailClipStart"]=state.lastConfirmedSegmentEndSeconds
            let source=[confirmed,tailText].filter{!$0.isEmpty}.joined(separator:" ")
            result["source"]=source;result["asrAfterStopSeconds"]=now()-stopped
            offer(source,final:true);if let worker { await worker.value }
            if let failure { throw failure }
            result["afterStopSeconds"]=now()-stopped
            result["translation"]=translations.compactMap{$0["translation"] as? String}.joined(separator:" ")
            result["thermalEnd"]=ProcessInfo.processInfo.thermalState.rawValue;result["thermalMax"]=thermalMax;result["peakFootprint"]=monitor.peakFootprint
            result["status"]="complete";save();report("Complete")
        } catch { result["status"]="failed";result["error"]=error.localizedDescription;save();report("Failed: " + error.localizedDescription) }
        await kit?.unloadModels();await mt.unload()
    }
}
