import XCTest
@testable import OfflineCore

private actor CameraMT: TranslationBackend {
    var progressCallback: (@Sendable (TranslationProgress) -> Void)?
    func emitProgress(_ value: TranslationProgress) { progressCallback?(value) }
    var holdEveryRequest = false
    func holdRequests() { holdEveryRequest = true }
    var partial: (@Sendable (String) -> Void)?
    func emitPartial(_ text: String) { partial?(text) }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void, partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        self.progressCallback = progress
        self.partial = partial
        return try await translate(text: text, source: source, target: target)
    }
    var documents: [TranslationDocument] = []
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, document: TranslationDocument,
                   progress: @escaping @Sendable (TranslationProgress) -> Void, partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        documents.append(document)
        return try await translate(text: text, source: source, target: target, progress: progress, partial: partial)
    }
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
        if shouldWait || holdEveryRequest { return try await withCheckedThrowingContinuation { pending = $0 } }
        return TranslationResult(text: "translated " + text, firstTokenSeconds: nil, processingSeconds: 0.25, fragments: 1)
    }
    func finish() { shouldWait = false; pending?.resume(returning: TranslationResult(text: "old translation", firstTokenSeconds: nil, processingSeconds: 0.25, fragments: 1)); pending = nil }
    var waiting: Bool { pending != nil }
    nonisolated func cancel() {}
    func unload() async { unloaded = true }
}
@MainActor final class ImageTranslationTests: XCTestCase {
    func testDocumentContextAcrossBlocksAndNoCacheFromDifferentScene() async throws {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: RetainedTranslationBackend(base: backend))
        await session.prepare(URL(fileURLWithPath: "/synthetic"))
        session.usesDocumentContext = true
        let blocks = [ImageTextBlock(text: "Насос работает.", box: .init(x: 0, y: 0, width: 1, height: 0.2)),
                      ImageTextBlock(text: "Проверка насоса.", box: .init(x: 0, y: 0.3, width: 1, height: 0.2))]
        session.submit(blocks, source: .russian, target: .english)
        await session.waitForIdle()
        var docs = await backend.documents
        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs[0].id, docs[1].id)
        XCTAssertEqual(docs[0].text, "Насос работает.\n\nПроверка насоса.")
        session.submit(blocks, source: .russian, target: .english)
        await session.waitForIdle()
        docs = await backend.documents
        XCTAssertEqual(docs.count, 4)
        XCTAssertNotEqual(docs[0].id, docs[2].id)
        session.usesDocumentContext = false
        session.submit(blocks, source: .russian, target: .english)
        await session.waitForIdle()
        let finalDocs = await backend.documents
        XCTAssertEqual(finalDocs.count, 4, "Disabled option uses the original overload")
        XCTAssertTrue(session.complete)
        await session.close()
    }

    func testWholeImageProgressSurvivesLocalChunkResetsAndCachedBlocks() async throws {
        let backend = CameraMT(); await backend.holdRequests()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        session.submit([block("aaaa"), block("bbbbbbbbbbbb", x: 0.5)], source: .english, target: .russian)
        while !(await backend.waiting) { await Task.yield() }
        XCTAssertEqual(session.progress?.totalCharacters, 16)
        XCTAssertEqual(session.progress?.totalParts, 2)
        await backend.emitProgress(.init(completedCharacters: 2, totalCharacters: 4, completedParts: 1, totalParts: 2, revision: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 2)
        XCTAssertEqual(session.progress?.completedParts, 0, "Inner chunks are not image blocks")
        await backend.finish()
        while await backend.inputs.count < 2 { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 4, "Do not hide progress between blocks")
        await backend.emitProgress(.init(completedCharacters: 0, totalCharacters: 12, completedParts: 0, totalParts: 1, revision: 0))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 4, "Next local request must not reset global progress")
        XCTAssertEqual(session.progress?.completedParts, 1)
        await backend.emitProgress(.init(completedCharacters: 6, totalCharacters: 12, completedParts: 1, totalParts: 2, revision: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 10)
        await backend.emitProgress(.init(completedCharacters: 0, totalCharacters: 12, completedParts: 0, totalParts: 3, revision: 2))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 10, "Retries must not rewind progress")
        await backend.finish(); await session.waitForIdle()
        XCTAssertTrue(session.complete)
        session.submit([block("aaaa"), block("cccccccccccc", x: 0.5)], source: .english, target: .russian)
        while !(await backend.waiting) { await Task.yield() }
        XCTAssertEqual(session.progress?.completedCharacters, 4, "Cached work counts immediately")
        XCTAssertEqual(session.progress?.totalCharacters, 16)
        session.clearScene()
        await backend.emitProgress(.init(completedCharacters: 12, totalCharacters: 12, completedParts: 1, totalParts: 1, revision: 1))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(session.progress, "Old callbacks must not revive a cleared scene")
        await backend.finish(); await session.waitForIdle(); await session.close()
    }

    func testImagePartialsNeverBecomeCompletedOrCachedAndIgnoreLateCallbacks() async {
        let backend = CameraMT()
        let active = ImageTranslationSession(backend: backend)
        active.showsTranslationPartials = true
        await active.prepare(URL(fileURLWithPath: "/fixture"))
        active.submit([block("first")], source: .english, target: .russian)
        while !(await backend.waiting) { await Task.yield() }
        await backend.emitPartial("unfinished")
        for _ in 0..<100 { if active.partialTranslation != nil { break }; await Task.yield() }
        XCTAssertEqual(active.displayedBlocks.map(\.translation), ["unfinished"])
        XCTAssertTrue(active.translated.isEmpty)
        XCTAssertFalse(active.complete)
        active.clearScene()
        await backend.emitPartial("late")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(active.displayedBlocks.isEmpty)
        XCTAssertNil(active.partialTranslation)
        await backend.finish(); await active.waitForIdle()
        active.submit([block("second")], source: .english, target: .russian)
        await active.waitForIdle()
        XCTAssertTrue(active.complete)
        await backend.emitPartial("too late")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(active.partialTranslation)
        await active.close(preservingResult: true)
        XCTAssertEqual(active.displayedBlocks.map(\.translation), active.translated.map(\.translation))
        XCTAssertFalse(active.displayedBlocks.isEmpty)
    }

    func testReconstructedParagraphReachesTranslatorAsOneRequest() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        let rows = [ImageTextBlock(text: "A company builds housing,", box: ImageTextBox(x: 0.02, y: 0.3, width: 0.9, height: 0.18)),
                    ImageTextBlock(text: "community and technology.", box: ImageTextBox(x: 0.02, y: 0.5, width: 0.9, height: 0.18))]
        session.submit(ImageTextLayout.paragraphs(rows), source: .english, target: .russian)
        await session.waitForIdle()
        XCTAssertTrue(session.complete)
        XCTAssertEqual(session.translated.map(\.original), ["A company builds housing, community and technology."])
        let inputs = await backend.inputs
        XCTAssertEqual(inputs, ["en:A company builds housing, community and technology."])
        await session.close()
    }

    func testImageTimingSumsCurrentTranslationWorkAndClearsForNewScene() async {
        let backend = CameraMT(); await backend.finish()
        let session = ImageTranslationSession(backend: backend)
        await session.prepare(URL(fileURLWithPath: "/fixture"))
        XCTAssertNil(session.timing)
        session.submit([block("first"), block("second", x: 0.5)], source: .english, target: .russian, recognitionSeconds: 0.1)
        await session.waitForIdle()
        XCTAssertEqual(session.timing?.recognitionSeconds, 0.1)
        XCTAssertEqual(session.timing?.translationSeconds, 0.5)
        session.submit([block("first"), block("second", x: 0.5)], source: .english, target: .russian, recognitionSeconds: 0.2)
        await session.waitForIdle()
        XCTAssertEqual(session.timing?.recognitionSeconds, 0.2)
        XCTAssertEqual(session.timing?.translationSeconds, 0, "Cached translations do not run inference again")
        await session.close(preservingResult: true)
        XCTAssertNotNil(session.timing)
        session.clearScene()
        XCTAssertNil(session.timing)
    }

    func testImageTimingIgnoresWorkFromSupersededScene() async {
        let backend = CameraMT()
        // A controllable backend keeps the first scene in flight while it is replaced.
        let active = ImageTranslationSession(backend: backend)
        await active.prepare(URL(fileURLWithPath: "/fixture"))
        active.submit([block("old")], source: .english, recognitionSeconds: 9)
        while !(await backend.waiting) { await Task.yield() }
        active.submit([block("new")], source: .english, recognitionSeconds: 0.2)
        await backend.finish(); await active.waitForIdle()
        XCTAssertEqual(active.timing?.recognitionSeconds, 0.2)
        XCTAssertEqual(active.timing?.translationSeconds, 0.25)
        await active.close()
    }

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
