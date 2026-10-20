import XCTest
@testable import OfflineCore

private actor ResidencySpy: TranslationBackend {
    var loads = 0, frees = 0, calls = 0
    var loaded = false
    var failLoad = false
    func failNextLoad() { failLoad = true }
    func load(modelURL: URL) async throws {
        loads += 1
        if failLoad { failLoad = false; throw PipelineError.modelLoad }
        loaded = true
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        XCTAssertTrue(loaded); calls += 1
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(loaded, "Idle expiry must not unload during inference")
        return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async { frees += 1; loaded = false }
    func counts() -> [Int] { [loads, frees, calls] }
}

final class RetainedTranslationTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/synthetic/model")
    func testReuseExpiryReloadAndExplicitUnload() async throws {
        let spy = ResidencySpy()
        let cache = RetainedTranslationBackend(base: spy, idleSeconds: 0.03)
        try await cache.load(modelURL: url, model: .index9B)
        for _ in 0..<2 { _ = try await cache.translate(text: "hello", source: .english, target: .russian) }
        let warm = await spy.counts(); XCTAssertEqual(warm, [1, 0, 2])
        try await Task.sleep(nanoseconds: 100_000_000)
        let idle = await spy.counts(); XCTAssertEqual(idle, [1, 1, 2])
        _ = try await cache.translate(text: "again", source: .english, target: .russian)
        let reloaded = await spy.counts(); XCTAssertEqual(reloaded, [2, 1, 3])
        await cache.unload()
        do { _ = try await cache.translate(text: "bad", source: .english, target: .russian); XCTFail("Explicit unload must forget selection") } catch {}
    }
    func testConfigureAndConcurrentRequestsDoNotUnloadActiveModel() async throws {
        let spy = ResidencySpy(), url = self.url
        let cache = RetainedTranslationBackend(base: spy, idleSeconds: 10)
        try await cache.load(modelURL: url, model: .index9B)
        async let a = cache.translate(text: "a", source: .english, target: .russian)
        async let b = cache.translate(text: "b", source: .english, target: .russian)
        try await Task.sleep(nanoseconds: 10_000_000)
        await cache.setIdleTimeout(0.02)
        _ = try await (a, b)
        let active = await spy.counts(); XCTAssertEqual(active, [1, 0, 2])
        try await Task.sleep(nanoseconds: 100_000_000)
        let idle = await spy.counts(); XCTAssertEqual(idle, [1, 1, 2])
        try await cache.load(modelURL: url, model: .index2B)
        _ = try await cache.translate(text: "new", source: .english, target: .russian)
        let switched = await spy.counts(); XCTAssertEqual(switched[0], 2)
        await cache.unload()
    }
    func testFailedReloadCanRecoverAndCancelledWaiterDoesNotRun() async throws {
        let spy = ResidencySpy()
        let backend = RetainedTranslationBackend(base: spy, idleSeconds: 0.02)
        try await backend.load(modelURL: url, model: .index9B)
        try await Task.sleep(nanoseconds: 80_000_000)
        await spy.failNextLoad()
        do { _ = try await backend.translate(text: "failure", source: .english, target: .russian); XCTFail("Load should fail") } catch {}
        await backend.setIdleTimeout(300)
        let active = Task { try await backend.translate(text: "active", source: .english, target: .russian) }
        try await Task.sleep(nanoseconds: 10_000_000)
        let queued = Task { try await backend.translate(text: "cancelled", source: .english, target: .russian) }
        queued.cancel()
        _ = try await active.value
        do { _ = try await queued.value; XCTFail("Cancelled request must not run") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        let counts = await spy.counts(); XCTAssertEqual(counts[0], 3); XCTAssertEqual(counts[2], 1)
        await backend.unload()
    }
    func testChangingModelReleasesPreviousAndSameSelectionReuses() async throws {
        let spy = ResidencySpy()
        let backend = RetainedTranslationBackend(base: spy, idleSeconds: 300)
        try await backend.load(modelURL: url, model: .index9B)
        try await backend.load(modelURL: url, model: .index9B)
        let same = await spy.counts(); XCTAssertEqual(same, [1, 0, 0])
        try await backend.load(modelURL: url, model: .index2B)
        let changed = await spy.counts(); XCTAssertEqual(changed, [2, 1, 0])
        await backend.unload()
    }
    func testChunkPlanPreservesEveryCharacterAndBudget() throws {
        for input in ["First sentence. Second sentence.\nThird line.\n\nNext paragraph.", String(repeating: "猫🙂", count: 40), "  leading and trailing  ", ""] {
            let chunks = try TranslationChunks.plan(input, limit: 17, count: { $0.count })
            XCTAssertEqual(chunks.joined(), input)
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 17 })
        }
        XCTAssertThrowsError(try TranslationChunks.plan("x", limit: 1, count: { _ in 2 }))
    }
}
