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
