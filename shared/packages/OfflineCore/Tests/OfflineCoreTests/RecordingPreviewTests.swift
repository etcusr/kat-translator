import XCTest
@testable import OfflineCore

@MainActor final class RecordingPreviewTests: XCTestCase {
    func testAutomaticPreviewKeepsSelectedTargetBeyondRussianEnglish() async {
        var directions: [String] = []
        let worker = RecordingPreviewCoordinator(source: nil, target: .french,
            snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, source in
                XCTAssertNil(source)
                return ASRResult(text: "Доброго ранку.", language: .lang_uk, processingSeconds: 0.1)
            }, translate: { _, source, target in
                directions.append(source.rawValue + "-" + target.rawValue)
                return TranslationResult(text: "Bonjour.", firstTokenSeconds: nil, processingSeconds: 0.2, fragments: 1)
            }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000)
        let result = await worker.finish()
        XCTAssertEqual(directions, ["uk-fr"])
        XCTAssertEqual(result.target, .french); XCTAssertEqual(result.source, .lang_uk)
        XCTAssertEqual(result.translatedText, "Bonjour.")
    }
    func testSameLanguagePreviewSkipsTranslation() async {
        let worker = RecordingPreviewCoordinator(source: nil, target: .english,
            snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in ASRResult(text: "Good morning.", language: .english, processingSeconds: 0.1) },
            translate: { _, _, _ in XCTFail("No inference when already in the target language"); throw PipelineError.inference },
            prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000)
        let result = await worker.finish()
        XCTAssertEqual(result.translatedText, "Good morning.")
        XCTAssertEqual(result.mtSeconds, 0)
    }
    func testCommitsOnceAndNeverProcessesSilenceTwice() async throws {
        var ranges: [Range<Int>] = []; var translations = 0; var drafts = 0
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { range in
            ranges.append(range); return CapturedAudio(samples: Array(repeating: 0.1, count: range.count))
        }, recognize: { _, _ in ASRResult(text: "Hello.", language: .russian, processingSeconds: 0.1) }, translate: { _, _, _ in
            translations += 1; return TranslationResult(text: "Hi.", firstTokenSeconds: nil, processingSeconds: 0.2, fragments: 1)
        }, prepareSpeech: nil, publish: { _ in drafts += 1 })
        worker.offer(end: 32_000)
        await worker.waitForIdle()
        worker.offer(end: 32_000)
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 32_000)
        XCTAssertEqual(result.sourceText, "Hello.")
        XCTAssertEqual(result.translatedText, "Hi.")
        XCTAssertEqual(ranges, [0..<32_000]); XCTAssertEqual(translations, 1); XCTAssertEqual(drafts, 1)
    }
    func testIncompleteSentenceStaysUncommittedAndMergesWithNextBoundary() async {
        var ranges: [Range<Int>] = []
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { range in
            ranges.append(range); return CapturedAudio(samples: [Float(range.upperBound)])
        }, recognize: { audio, _ in ASRResult(text: audio.samples[0] < 60_000 ? "Do not" : "Do not cancel.", language: .russian, processingSeconds: 0) }, translate: { text, _, _ in
            TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
        }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000); await worker.waitForIdle()
        worker.offer(end: 64_000)
        let result = await worker.finish()
        XCTAssertEqual(ranges, [0..<32_000, 0..<64_000])
        XCTAssertEqual(result.translatedText, "Do not cancel.")
    }
    func testCancelRejectsLateTranslation() async {
        var continuation: CheckedContinuation<TranslationResult, Never>?
        var published = false
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in ASRResult(text: "Hello.", language: .russian, processingSeconds: 0) }, translate: { _, _, _ in
                await withCheckedContinuation { continuation = $0 }
            }, prepareSpeech: nil, publish: { _ in published = true })
        worker.offer(end: 32_000)
        while continuation == nil { await Task.yield() }
        worker.cancel()
        continuation?.resume(returning: TranslationResult(text: "late", firstTokenSeconds: nil, processingSeconds: 0, fragments: 1))
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 0); XCTAssertFalse(published)
    }
    func testFailedWorkLeavesAudioForFinalization() async {
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in throw PipelineError.inference }, translate: { _, _, _ in XCTFail("No MT on ASR error"); throw PipelineError.inference }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000)
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 0); XCTAssertEqual(result.fallbackReason, "preview-error")
    }
    func testPressureDuringRecognitionDoesNotStartTranslation() async {
        var continuation: CheckedContinuation<ASRResult, Never>?
        var translated = false
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in await withCheckedContinuation { continuation = $0 } },
            translate: { _, _, _ in translated = true; throw PipelineError.inference }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000)
        while continuation == nil { await Task.yield() }
        worker.suspend(reason: "memory-warning")
        continuation?.resume(returning: ASRResult(text: "Hello.", language: .russian, processingSeconds: 0.1))
        let result = await worker.finish()
        XCTAssertFalse(translated); XCTAssertEqual(result.committedSamples, 0)
        XCTAssertEqual(result.fallbackReason, "memory-warning")
    }
    func testBacklogCoalescesWithoutDroppingAudioRange() async {
        var continuation: CheckedContinuation<ASRResult, Never>?
        var ranges: [Range<Int>] = []; var count = 0
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { range in
            ranges.append(range); return CapturedAudio(samples: [0.1])
        }, recognize: { _, _ in
            count += 1
            if count == 1 { return await withCheckedContinuation { continuation = $0 } }
            return ASRResult(text: "Next.", language: .russian, processingSeconds: 0)
        }, translate: { text, _, _ in TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000)
        while continuation == nil { await Task.yield() }
        worker.offer(end: 64_000); worker.offer(end: 96_000)
        continuation?.resume(returning: ASRResult(text: "First.", language: .russian, processingSeconds: 0))
        let result = await worker.finish()
        XCTAssertEqual(ranges, [0..<32_000, 32_000..<96_000])
        XCTAssertEqual(result.committedSamples, 96_000)
        XCTAssertEqual(result.translatedText, "First. Next.")
    }
    func testBoundaryOnlyAfterSpeechAndQuietInterval() {
        var policy = RecordingPreviewBoundary()
        for _ in 0..<100 { XCTAssertNil(policy.observe(speech: false, sampleCount: 512)) }
        for _ in 0..<100 { XCTAssertNil(policy.observe(speech: true, sampleCount: 512)) }
        var boundaries: [Int] = []
        for _ in 0..<100 { if let end = policy.observe(speech: false, sampleCount: 512) { boundaries.append(end) } }
        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(policy.lastSpeechEnd, 102_400)
        XCTAssertGreaterThan(boundaries[0], policy.lastSpeechEnd)
    }
}
