import XCTest
@testable import OfflineCore

private actor CameraMT: TranslationBackend {
    var inputs: [String] = []
    var targets: [SpeechLanguage] = []
    var models: [TranslationModel] = []
    var pending: CheckedContinuation<TranslationResult, Error>?
    var shouldWait = true
    var unloaded = false
    func load(modelURL: URL) async throws {}
    func load(modelURL: URL, model: TranslationModel) async throws { models.append(model) }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        inputs.append(source.rawValue + ":" + text); targets.append(target)
        if shouldWait { return try await withCheckedThrowingContinuation { pending = $0 } }
        return TranslationResult(text: "translated " + text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
    }
    func finish() { shouldWait = false; pending?.resume(returning: TranslationResult(text: "old translation", firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)); pending = nil }
    var waiting: Bool { pending != nil }
    nonisolated func cancel() {}
    func unload() async { unloaded = true }
}
@MainActor final class ImageTranslationTests: XCTestCase {
    func testAlreadyInTargetLanguageDoesNotRunTranslation() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("Hello")], source: .english, target: .english)
        await session.waitForIdle()
        XCTAssertTrue(session.complete)
        XCTAssertEqual(session.translated.map(\.translation), ["Hello"])
        let inputs = await backend.inputs
        XCTAssertTrue(inputs.isEmpty)
        await session.close()
    }
    func testCameraPassesSelectedModelAndCanSwitchAfterClosing() async {
        let backend = CameraMT(), url = URL(fileURLWithPath: "/fixture")
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(url, model: .index9B)
        XCTAssertTrue(session.ready)
        await session.close()
        await session.prepare(url, model: .gemma4B)
        let models = await backend.models
        XCTAssertEqual(models, [.index9B, .gemma4B])
    }

    func testResultSurvivesModelUnloadUntilExplicitClear() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("hello")], source: .english, target: .russian)
        await session.waitForIdle()
        let result = session.translated.map(\.translation)
        await session.close(preservingResult: true)
        XCTAssertFalse(session.ready)
        XCTAssertTrue(session.complete)
        XCTAssertEqual(session.translated.map(\.translation), result)
        let unloaded = await backend.unloaded; XCTAssertTrue(unloaded)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        XCTAssertEqual(session.translated.map(\.translation), result)
        session.clearScene()
        XCTAssertTrue(session.translated.isEmpty); XCTAssertFalse(session.complete)
        await session.close()
    }
    private func block(_ text: String, x: Double = 0) -> ImageTextBlock {
        ImageTextBlock(text: text, box: ImageTextBox(x: x, y: 0.2, width: 0.4, height: 0.1))
    }
    func testLatestSceneNeverGetsOldLabelsAndRepeatedTextUsesCache() async {
        let backend = CameraMT(); let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("old")], source: .english)
        while !(await backend.waiting) { await Task.yield() }
        session.submit([block("new")], source: .english)
        XCTAssertTrue(session.translated.isEmpty)
        await backend.finish(); await session.waitForIdle()
        XCTAssertEqual(session.translated.map(\.translation), ["translated new"])
        session.submit([block("new", x: 0.5)], source: .english)
        await session.waitForIdle()
        let inputs = await backend.inputs
        XCTAssertEqual(inputs, ["en:old", "en:new"])
        XCTAssertEqual(session.translated.first?.box.x, 0.5)
        session.clearScene(); XCTAssertTrue(session.translated.isEmpty)
    }
    func testLanguageChangeDoesNotReuseOppositeTranslation() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("text")], source: .english); await session.waitForIdle()
        session.submit([block("text")], source: .russian); await session.waitForIdle()
        let inputs = await backend.inputs
        XCTAssertEqual(inputs, ["en:text", "ru:text"])
        XCTAssertTrue(session.complete)
    }
    func testCloseWaitsForNativeWorkAndDoesNotPublishItsResult() async {
        let backend = CameraMT(); let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("old")], source: .english)
        while !(await backend.waiting) { await Task.yield() }
        let closing = Task { await session.close() }
        for _ in 0..<20 { await Task.yield() }
        let early = await backend.unloaded
        XCTAssertFalse(early)
        await backend.finish(); await closing.value
        XCTAssertTrue(session.translated.isEmpty); XCTAssertFalse(session.ready)
    }
    func testTargetChangeInvalidatesCameraCache() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("hello")], source: .english, target: .french); await session.waitForIdle()
        session.submit([block("hello")], source: .english, target: .japanese); await session.waitForIdle()
        let targets = await backend.targets
        XCTAssertEqual(targets, [.french, .japanese])
        XCTAssertTrue(session.complete)
    }
    func testBoxesClipToImageWithoutNegativeArea() {
        let b = ImageTextBox(x: -0.1, y: 0.9, width: 0.5, height: 0.4)
        XCTAssertEqual(b.x, 0); XCTAssertEqual(b.width, 0.4, accuracy: 0.00001)
        XCTAssertEqual(b.height, 0.1, accuracy: 0.00001)
    }
}
