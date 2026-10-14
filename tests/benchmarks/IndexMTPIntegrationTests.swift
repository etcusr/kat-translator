import XCTest
import Foundation
import Darwin
import OfflineCore
@testable import OfflineTranslator

private final class IndexRuntime {
    typealias Load = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Create = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Count = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
    typealias Run = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>, Int, UnsafeMutablePointer<Double>) -> Int32
    let library: UnsafeMutableRawPointer
    let load: Load, free: Free, create: Create, cancel: Free, freeFlag: Free, run: Run, count: Count
    init() throws {
        let handle = try XCTUnwrap(dlopen(Bundle.main.privateFrameworksURL!.appendingPathComponent("TranslationRuntime.framework/TranslationRuntime").path, RTLD_NOW))
        library = handle
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T { unsafeBitCast(try XCTUnwrap(dlsym(handle, name)), to: T.self) }
        load = try symbol("ot_mt_load", Load.self); free = try symbol("ot_mt_free", Free.self)
        create = try symbol("ot_mt_flag_create", Create.self); cancel = try symbol("ot_mt_flag_cancel", Free.self)
        freeFlag = try symbol("ot_mt_flag_free", Free.self); run = try symbol("ot_mt_run", Run.self); count = try symbol("ot_mt_count", Count.self)
    }
    deinit { dlclose(library) }
}

/// Opt-in real on-device Index tests. No downloads, ASR, TTS, or user preference changes.
final class IndexMTPIntegrationTests: XCTestCase {
    private func modelURL() async throws -> URL {
        let store = ModelStore(root: ModelDownloader.root.appendingPathComponent("Models"))
        let installed = try await store.installedURL(for: ModelCatalog.indexTranslation)
        return try XCTUnwrap(installed)
    }
    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["KAT_MTP_INTEGRATION"] == "1" else { throw XCTSkip("Real Index device tests") }
    }
    func testCancelledOverlongRequest() async throws {
        try requireOptIn()
        let api = try IndexRuntime(), url = try await modelURL()
        let engine = try XCTUnwrap(api.load(url.path)); defer { api.free(engine) }
        let flag = try XCTUnwrap(api.create()); defer { api.freeFlag(flag) }
        api.cancel(flag)
        var output = [CChar](repeating: 65, count: 64), first = 0.0
        let code = api.run(engine, "", String(repeating: "word ", count: 2000), "", flag, &output, output.count, &first)
        XCTAssertEqual(code, 2, "Cancelled work must not ask Swift to split and retry an overlong input")
        XCTAssertEqual(output[0], 0)
        XCTAssertEqual(first, -1)
    }
    func testInferenceCancellationLimitsAndReuse() async throws {
        try requireOptIn()
        let api = try IndexRuntime(), url = try await modelURL()
        let engine = try XCTUnwrap(api.load(url.path)); defer { api.free(engine) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "index-mtp-cases", withExtension: "json"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
        let suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        func prefix(_ target: String) -> String { "<|im_start|>user\n请将以下文本翻译为\(target == "ru" ? "俄语" : "英语")，直接输出翻译结果，不要进行任何解释。\n\n" }
        var rows: [[String: Any]] = []
        func execute(_ text: String, target: String = "ru", capacity: Int = 65536, cancelAfter: Double? = nil) throws -> (Int32, String, Double, Double) {
            let flag = try XCTUnwrap(api.create()); defer { api.freeFlag(flag) }
            let completed = DispatchGroup()
            if let delay = cancelAfter {
                completed.enter()
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { api.cancel(flag); completed.leave() }
            }
            var output = [CChar](repeating: 65, count: capacity), first = -1.0
            let start = ProcessInfo.processInfo.systemUptime
            let code = api.run(engine, prefix(target), text, suffix, flag, &output, output.count, &first)
            let seconds = ProcessInfo.processInfo.systemUptime - start
            completed.wait()
            return (code, String(cString: output), seconds, first)
        }
        let source = try XCTUnwrap(cases.first?["text"] as? String)
        let original = try execute(source)
        XCTAssertEqual(original.0, 0); XCTAssertFalse(original.1.isEmpty)
        for delay in [0.02, 1.0] {
            let cancelled = try execute(try XCTUnwrap(cases.first(where: { $0["id"] as? String == "synthetic_long_ru" })?["text"] as? String), target: "en", cancelAfter: delay)
            XCTAssertEqual(cancelled.0, 2); XCTAssertEqual(cancelled.1, "")
            let recovered = try execute(source)
            XCTAssertEqual(recovered.0, 0); XCTAssertEqual(recovered.1, original.1, "Cancelled speculative state must not leak into the next request")
            rows.append(["check": "cancel-and-reuse", "delay": delay, "cancelSeconds": cancelled.2, "code": cancelled.0])
        }
        let limited = try execute(source, capacity: 2)
        XCTAssertEqual(limited.0, 1); XCTAssertEqual(limited.1, "", "Partial text must never escape a limit failure")
        let overlong = try execute(String(repeating: "word ", count: 2000))
        XCTAssertEqual(overlong.0, 1); XCTAssertEqual(overlong.1, "")
        // Cross the 512-token prefill batch boundary; stop at the output buffer limit.
        let longInput = String(repeating: source + " ", count: 40)
        let inputTokens = api.count(engine, prefix("ru"), longInput, suffix)
        XCTAssertGreaterThan(inputTokens, 512); XCTAssertLessThanOrEqual(inputTokens, 1536)
        let longPrefill = try execute(longInput, capacity: 2)
        XCTAssertEqual(longPrefill.0, 1); XCTAssertEqual(longPrefill.1, "")
        let recovered = try execute(source)
        XCTAssertEqual(recovered.0, 0); XCTAssertEqual(recovered.1, original.1)
        for item in cases {
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            let result = try execute(try XCTUnwrap(item["text"] as? String), target: try XCTUnwrap(item["to_language"] as? String))
            XCTAssertEqual(result.0, 0); XCTAssertFalse(result.1.isEmpty)
            rows.append(["id": item["id"]!, "translation": result.1, "seconds": result.2, "firstTokenSeconds": result.3,
                         "code": result.0, "thermalBefore": thermal, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
        }
        // A long numeric list is copied by translation, exhausting the fixed response
        // window; this exercises the final target-only rounds, not just a small buffer.
        let numericInput = (1...300).map(String.init).joined(separator: ", ")
        let numericTokens = api.count(engine, prefix("ru"), numericInput, suffix)
        XCTAssertLessThanOrEqual(numericTokens, 1536)
        let exhausted = try execute(numericInput)
        XCTAssertEqual(exhausted.0, 1); XCTAssertEqual(exhausted.1, "")
        let finalRecovery = try execute(source)
        XCTAssertEqual(finalRecovery.0, 0); XCTAssertEqual(finalRecovery.1, original.1)
        rows.append(["check": "context-limit-and-reuse", "code": exhausted.0, "seconds": exhausted.2])
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("index-mtp-production-validation.json")
        try JSONSerialization.data(withJSONObject: ["rows": rows, "modelSHA256": ModelCatalog.indexTranslation.sha256], options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
    @MainActor func testProductionPipelineWithVoiceResources() async throws {
        try requireOptIn()
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        let url = try await modelURL()
        let recognition = RecognitionPreference.restoredSelection(UserDefaults.standard.string(forKey: "recognitionPreference"))
        let pipeline = ConversationPipeline(asr: RoutedASRBackend(), translator: RoutedTranslationBackend(),
                                            speech: SherpaSpeechBackend(), player: SpeechPlayer())
        let files = PipelineFiles(asr: packages.primaryRecognition(for: recognition), translation: url,
                                  voices: packages.selectedVoiceDirectories, voiceModelIDs: packages.selectedVoiceModelIDs,
                                  translationModel: .index9B, omnilingual: packages.omnilingualDirectory,
                                  ultra: packages.recognition.ultra, recognitionPreference: recognition)
        await pipeline.prepare(files, memorySaving: false, recognitionLanguage: .russian, resultMode: .voice)
        XCTAssertTrue(pipeline.isReady); XCTAssertNil(pipeline.error)
        await pipeline.run(audio: nil, text: "В этом синтетическом тесте библиотека откроется 18 октября.",
                           source: .russian, target: .english, speakResult: true,
                           inputMode: "mtp-integration", thermal: "test", resultMode: .voice)
        XCTAssertNil(pipeline.voiceFields.error)
        XCTAssertTrue(pipeline.voiceFields.translatedText.contains("October"))
        XCTAssertTrue(pipeline.voiceFields.translatedText.contains("18"))
        print("MTP_PIPELINE_TRANSLATION", pipeline.voiceFields.translatedText)
        print("MTP_PIPELINE_SPEECH", pipeline.hasVoiceTranslationSpeech)
        pipeline.clearTemporarySpeech()
        await pipeline.unload()
    }

}
