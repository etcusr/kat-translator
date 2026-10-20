import XCTest
import OfflineCore
@testable import Kat_translator

private final class MLXPartialProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    func receive(_ text: String) { lock.lock(); defer { lock.unlock() }; texts.append(text) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return texts }
}

final class MacMLXIntegrationTests: XCTestCase {
    func testChunksDefaultOnAndPreserveExplicitChoice() throws {
        let suite = "kat-chunk-default-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(MacTranslationOptions.chunksEnabled(in: defaults))
        defaults.set(false, forKey: "macExperimentalTranslationChunks")
        XCTAssertFalse(MacTranslationOptions.chunksEnabled(in: defaults))
        defaults.set(true, forKey: "macExperimentalTranslationChunks")
        XCTAssertTrue(MacTranslationOptions.chunksEnabled(in: defaults))
    }

    func testPackagedRuntimeCancellationLimitsAndRouting() async throws {
        guard ProcessInfo.processInfo.environment["KAT_MLX_INTEGRATION"] == "1" else {
            throw XCTSkip("Explicit local-model test only")
        }
        let model = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KAT_MLX_MODEL_PATH"]!)
        let resources = Bundle.main.resourceURL!
        let engine = try XCTUnwrap(kat_mlx_load(resources.path, model.path))
        let request = TranslationModel.index9B.request(text: "В этом синтетическом тесте библиотека откроется 18 октября. Можно ли вернуть книгу?", source: .russian, target: .english)
        let count = kat_mlx_count(engine, request.prefix, request.text, request.suffix)
        XCTAssertGreaterThan(count, 0) // Synthetic fixture replaces private input.
        func run(_ text: String, capacity: Int = 65536, precancel: Bool = false, during: Bool = false) -> (Int32, String) {
            let flag = kat_mlx_flag_create()!
            defer { kat_mlx_flag_free(flag) }
            if precancel { kat_mlx_flag_cancel(flag) }
            let timer = DispatchGroup()
            if during {
                timer.enter()
                DispatchQueue.global().asyncAfter(deadline: .now()+0.05) { kat_mlx_flag_cancel(flag); timer.leave() }
            }
            var out = [CChar](repeating: 0, count: capacity); var first = -1.0
            let code = kat_mlx_run(engine, request.prefix, text, request.suffix, flag, &out, out.count, &first)
            timer.wait()
            if code != 0 { XCTAssertEqual(first, -1) }
            return (code, String(cString: out))
        }
        let cancelled = run(String(repeating: "1 ", count: 2000), precancel: true)
        XCTAssertEqual(cancelled.0, 2); XCTAssertEqual(cancelled.1, "")
        let overflow = run(request.text, capacity: 2)
        XCTAssertEqual(overflow.0, 1); XCTAssertEqual(overflow.1, "")
        let clean = run(request.text)
        XCTAssertEqual(clean.0, 0)
        XCTAssertFalse(clean.1.isEmpty) // Private golden output intentionally removed.
        let cancelledDuring = run(request.text, during: true)
        XCTAssertEqual(cancelledDuring.0, 2); XCTAssertEqual(cancelledDuring.1, "")
        let reused = run(request.text)
        XCTAssertEqual(reused.0, 0); XCTAssertEqual(reused.1, clean.1)
        kat_mlx_free(engine)
        let backend = RoutedTranslationBackend()
        try await backend.load(modelURL: model, model: .index9B)
        let partials = MLXPartialProbe()
        let routed = try await backend.translate(text: request.text, source: .russian, target: .english,
                                                 progress: { _ in }, partial: { partials.receive($0) })
        XCTAssertEqual(routed.text, clean.1)
        XCTAssertNotNil(routed.firstTokenSeconds)
        let snapshots = partials.values
        XCTAssertFalse(snapshots.isEmpty, "Default Mac Index 9B must deliver partials through routed MLX")
        XCTAssertTrue(snapshots.contains { !$0.isEmpty && $0 != routed.text && routed.text.hasPrefix($0) },
                      "At least one genuine partial must precede the final translation")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(partials.values, snapshots, "No callbacks after completion")
        let cancelledPartials = MLXPartialProbe()
        do {
            _ = try await backend.translate(text: request.text, source: .russian, target: .english,
                                            progress: { _ in }, partial: {
                cancelledPartials.receive($0); backend.cancel()
            })
            XCTFail("Cancellation from a partial must abort the request")
        } catch is CancellationError { }
        XCTAssertEqual(cancelledPartials.values.count, 1)
        let afterCancel = try await backend.translate(text: request.text, source: .russian, target: .english)
        XCTAssertEqual(afterCancel.text, clean.1)
        XCTAssertEqual(cancelledPartials.values.count, 1, "Reused engine must not call an old request")
        await backend.unload()
        // MLX and the existing Thai speech frontend share the packaged interpreter.
        XCTAssertEqual(ot_wayu_frontend_init(resources.path), 1)
        var speechTokens = [Int64](repeating: 0, count: 512)
        XCTAssertGreaterThan(ot_wayu_frontend_tokens("สวัสดีครับ", &speechTokens, Int32(speechTokens.count)), 0)
        print("MAC_MLX_INTEGRATION_OK count=\(count) mtp2=true cancel=true reuse=true routed=true partials=\(snapshots.count) partialCancel=true")
    }
}

private final class ResidencyMLXProbe: TranslationBackend, @unchecked Sendable {
    let backend: MLXTranslationBackend
    private let lock = NSLock()
    private var loadCount = 0
    init(chunks: Bool) { backend = MLXTranslationBackend(chunkingEnabled: { chunks }) }
    var loads: Int { lock.lock(); defer { lock.unlock() }; return loadCount }
    private func loaded() { lock.lock(); loadCount += 1; lock.unlock() }
    func load(modelURL: URL) async throws { try await backend.load(modelURL: modelURL); loaded() }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await backend.translate(text: text, source: source, target: target)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        try await backend.translate(text: text, source: source, target: target, progress: progress, partial: partial)
    }
    func cancel() { backend.cancel() }
    func unload() async { await backend.unload() }
}
private final class TranslationArrivalProbe: @unchecked Sendable {
    private let lock = NSLock()
    let start = ProcessInfo.processInfo.systemUptime
    private var firstText: Double?, firstChunk: Double?
    private var last = ""
    func partial(_ value: String) { lock.lock(); defer { lock.unlock() }; if firstText == nil && !value.isEmpty { firstText = ProcessInfo.processInfo.systemUptime - start }; last = value }
    func progress(_ value: TranslationProgress) { lock.lock(); defer { lock.unlock() }; if firstChunk == nil && value.completedParts > 0 { firstChunk = ProcessInfo.processInfo.systemUptime - start } }
    var values: [String: Any] { lock.lock(); defer { lock.unlock() }; return ["firstTextSeconds": firstText ?? -1, "firstChunkSeconds": firstChunk ?? -1, "lastPartial": last] }
}
extension MacMLXIntegrationTests {
    func testResidentModelAndOptionalChunks() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KAT_RESIDENCY_INTEGRATION"] == "1" else { throw XCTSkip("Explicit local-model residency test only") }
        let model = URL(fileURLWithPath: try XCTUnwrap(env["KAT_MLX_MODEL_PATH"]))
        let fixture = URL(fileURLWithPath: try XCTUnwrap(env["KAT_LONG_FIXTURE"]))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
        let long = try XCTUnwrap(cases.first { $0["id"] as? String == "en-extended" }?["text"] as? String)
        var measurements: [[String: Any]] = []
        for chunks in [false, true] {
            let spy = ResidencyMLXProbe(chunks: chunks)
            let cached = RetainedTranslationBackend(base: spy, idleSeconds: 300)
            try await cached.load(modelURL: model, model: .index9B)
            _ = try await cached.translate(text: "Hello, where is the airport?", source: .english, target: .russian)
            var outputs: [String] = []
            for repetition in 0..<2 {
                let probe = TranslationArrivalProbe()
                let result = try await cached.translate(text: long, source: .english, target: .russian, progress: { probe.progress($0) }, partial: { probe.partial($0) })
                XCTAssertEqual(spy.loads, 1, "Warm requests must not reload the model")
                outputs.append(result.text)
                var row = probe.values
                row["mode"] = chunks ? "chunks" : "whole"; row["repetition"] = repetition
                row["seconds"] = ProcessInfo.processInfo.systemUptime - probe.start; row["fragments"] = result.fragments; row["output"] = result.text
                measurements.append(row)
                if chunks { XCTAssertGreaterThan(result.fragments, 1); XCTAssertEqual(row["lastPartial"] as? String, result.text) }
            }
            XCTAssertEqual(outputs[0], outputs[1])
            await cached.setIdleTimeout(0.1)
            try await Task.sleep(nanoseconds: 300_000_000)
            _ = try await cached.translate(text: "Hello", source: .english, target: .russian)
            XCTAssertEqual(spy.loads, 2, "Request after idle unload must reload automatically")
            await cached.setIdleTimeout(300)
            do {
                _ = try await cached.translate(text: long, source: .english, target: .russian, progress: { _ in }, partial: { _ in cached.cancel() })
                XCTFail("Cancelling partial translation must abort")
            } catch is CancellationError {} catch { XCTFail("Unexpected cancellation: \(error)") }
            let recovery = try await cached.translate(text: "Hello", source: .english, target: .russian)
            XCTAssertFalse(recovery.text.isEmpty)
            await cached.unload()
        }
        let out = URL(fileURLWithPath: try XCTUnwrap(env["KAT_RESIDENCY_OUTPUT"]))
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        print("MAC_RESIDENCY_OK warmReuse=true idleReload=true chunks=true cancellation=true")
    }
}
