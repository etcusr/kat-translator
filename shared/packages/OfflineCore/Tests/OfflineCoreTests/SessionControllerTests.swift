import XCTest
@testable import OfflineCore
private actor DelayedBackend: ASRBackend {
    var calls = 0
    var continuations: [CheckedContinuation<ASRResult, Error>] = []
    var unloaded = false
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        calls += 1
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    nonisolated func cancel() {}
    func unload() async { unloaded = true }
    func resolve() {
        let list = continuations; continuations = []
        for item in list { item.resume(returning: ASRResult(text: "старый текст", language: .russian, processingSeconds: 1)) }
    }
}
@MainActor final class SessionControllerTests: XCTestCase {
    func testCancelledRecognitionDoesNotPublishLateText() async {
        let backend = DelayedBackend(); let session = SessionController(backend: backend)
        await session.load(URL(fileURLWithPath: "/fixture"))
        let running = Task { await session.recognize(CapturedAudio(samples: [0.1]), language: .russian) }
        while await backend.calls == 0 { await Task.yield() }
        session.cancel(); await backend.resolve(); await running.value
        XCTAssertEqual(session.transcript, "")
    }
    func testConcurrentRecognitionDoesNotReachBackend() async {
        let backend = DelayedBackend(); let session = SessionController(backend: backend)
        await session.load(URL(fileURLWithPath: "/fixture"))
        let first = Task { await session.recognize(CapturedAudio(samples: [0.1]), language: .russian) }
        while await backend.calls == 0 { await Task.yield() }
        let second = Task { await session.recognize(CapturedAudio(samples: [0.2]), language: .english) }
        for _ in 0..<100 { await Task.yield() }
        let calls = await backend.calls
        await backend.resolve(); await first.value; await second.value
        XCTAssertEqual(calls, 1)
    }
    func testUnloadWaitsForRecognitionBeforeFreeingContext() async {
        let backend = DelayedBackend(); let session = SessionController(backend: backend)
        await session.load(URL(fileURLWithPath: "/fixture"))
        let running = Task { await session.recognize(CapturedAudio(samples: [0.1]), language: .russian) }
        while await backend.calls == 0 { await Task.yield() }
        let unloading = Task { await session.unload() }
        for _ in 0..<100 { await Task.yield() }
        let early = await backend.unloaded
        await backend.resolve(); await running.value; await unloading.value
        XCTAssertFalse(early)
        XCTAssertFalse(session.isLoaded)
    }
    func testEveryUnloadCallerWaitsForActiveRecognition() async {
        let backend = DelayedBackend(); let session = SessionController(backend: backend)
        await session.load(URL(fileURLWithPath: "/fixture"))
        let running = Task { await session.recognize(CapturedAudio(samples: [0.1]), language: .russian) }
        while await backend.calls == 0 { await Task.yield() }
        let first = Task { await session.unload() }
        while !session.isUnloading { await Task.yield() }
        var secondReturned = false
        let second = Task { await session.unload(); secondReturned = true }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(secondReturned, "Removal callers must wait for context release too")
        await backend.resolve(); await running.value; await first.value; await second.value
        XCTAssertTrue(secondReturned)
    }
}
