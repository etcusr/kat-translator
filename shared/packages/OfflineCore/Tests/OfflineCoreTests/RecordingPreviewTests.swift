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
    // Audit 22.10 (iOS M5): without a confirmed sentence every pause re-recognized everything since the last
    // commit, up to the whole recording. Past the limit the preview stops; Stop processes the recording as usual.
    func testUnconfirmedPreviewWindowIsBounded() async {
        var longest = 0, recognitions = 0
        let worker = RecordingPreviewCoordinator(source: .russian, target: .english, snapshot: { range in
            longest = max(longest, range.count); return CapturedAudio(samples: Array(repeating: 0.1, count: range.count))
        }, recognize: { _, _ in
            recognitions += 1; return ASRResult(text: "и потом мы пошли дальше", language: .russian, processingSeconds: 0.1)
        }, translate: { _, _, _ in XCTFail("Nothing was confirmed"); throw PipelineError.inference }, prepareSpeech: nil, publish: { _ in })
        for second in stride(from: 5, through: 600, by: 5) { worker.offer(end: second * 16_000); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertLessThanOrEqual(longest, 90 * 16_000)
        XCTAssertEqual(recognitions, 18)
        XCTAssertEqual(result.fallbackReason, "window-limit")
        XCTAssertEqual(result.committedSamples, 0)
    }
    // Audit 22.10 (iOS M6): the final tail pass is tracked work, so cancel() stops it and waitForIdle() waits for it
    // instead of letting it finish outside the pipeline's view.
    func testCancelledFinalPassIsAwaited() async {
        var calls = 0, finalDone = false, translations = 0
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian, snapshot: { range in
            CapturedAudio(samples: Array(repeating: 0.1, count: range.count))
        }, recognize: { _, _ in
            calls += 1
            if calls == 1 { return ASRResult(text: "First", language: .english, processingSeconds: 0, segments: [ASRSegment(text: "First", endSample: 32_000)]) }
            defer { finalDone = true }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return ASRResult(text: "First second.", language: .english, processingSeconds: 0, segments: [ASRSegment(text: "First second.", endSample: 64_000)])
        }, translate: { text, _, _ in
            translations += 1; return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
        }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 32_000); await worker.waitForIdle()
        let finishing = Task { await worker.finish(end: 64_000, speechEnd: 64_000) }
        while calls < 2 { await Task.yield() }
        worker.cancel(); await worker.waitForIdle()
        XCTAssertTrue(finalDone, "waitForIdle returned while the final pass was still running")
        _ = await finishing.value
        XCTAssertEqual(translations, 0)
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
    func testTimedPreviewKeepsUnfinishedTailAndDoesNotTrustWindowEndPunctuation() async {
        var ranges: [Range<Int>] = []
        var translated: [String] = []
        var call = 0
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian, snapshot: { range in
            ranges.append(range); return CapturedAudio(samples: Array(repeating: 0.1, count: range.count))
        }, recognize: { _, _ in
            call += 1
            if call == 1 {
                return ASRResult(text: "First. And then.", language: .english, processingSeconds: 0,
                    segments: [.init(text: "First.", endSample: 32_000), .init(text: " And then.", endSample: 128_000)])
            }
            return ASRResult(text: "First. And then more", language: .english, processingSeconds: 0,
                segments: [.init(text: "First.", endSample: 32_000), .init(text: " And then more", endSample: 240_000)])
        }, translate: { text, _, _ in
            translated.append(text); return TranslationResult(text: "Первая.", firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
        }, prepareSpeech: nil, publish: { _ in })
        worker.offer(end: 128_000, endsInSilence: false); await worker.waitForIdle()
        worker.offer(end: 256_000, endsInSilence: false); await worker.waitForIdle()
        let result = await worker.finish()
        XCTAssertEqual(translated, ["First."])
        XCTAssertEqual(result.committedSamples, 32_000)
        XCTAssertEqual(ranges, [0..<128_000, 0..<256_000])
    }
    func testChangedWordsAreNotConfirmedByAnIdenticalSentenceEnding() async {
        var call = 0
        var texts: [String] = []
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { range in CapturedAudio(samples: Array(repeating: 0.1, count: range.count)) },
            recognize: { _, _ in
                call += 1
                switch call {
                case 1: return ASRResult(text: "It was in the garden. Next", language: .english, processingSeconds: 0,
                    segments: [.init(text: "It was in the garden.", endSample: 64_000), .init(text: " Next", endSample: 128_000)])
                case 2: return ASRResult(text: "They were in the garden. Next words", language: .english, processingSeconds: 0,
                    segments: [.init(text: "They were in the garden. Next words", endSample: 256_000)])
                default: return ASRResult(text: "We were in the garden. Next words continue", language: .english, processingSeconds: 0,
                    segments: [.init(text: "We were in the garden.", endSample: 65_280), .init(text: " Next words continue", endSample: 384_000)])
                }
            }, translate: { text, _, _ in texts.append(text); return TranslationResult(text: "В саду.", firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [128_000, 256_000, 384_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertTrue(texts.isEmpty)
        XCTAssertEqual(result.committedSamples, 0)
    }
    func testRetainsConfirmedAudioAsContextAndDoesNotDuplicateItsText() async {
        var ranges: [Range<Int>] = []
        var call = 0
        var translated: [String] = []
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { range in ranges.append(range); return CapturedAudio(samples: Array(repeating: 0.1, count: range.count)) },
            recognize: { _, _ in
                call += 1
                let first = ASRSegment(text: "Keep every word.", endSample: 32_000)
                let next = ASRSegment(text: " Next sentence.", endSample: 96_000)
                return ASRResult(text: call < 3 ? first.text : first.text + next.text, language: .english, processingSeconds: 0,
                    segments: call < 3 ? [first] : [first, next])
            }, translate: { text, _, _ in translated.append(text); return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [64_000, 96_000, 128_000, 160_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertEqual(ranges.map(\.lowerBound), [0, 0, 0, 0])
        XCTAssertEqual(translated, ["Keep every word.", "Next sentence."])
        XCTAssertEqual(result.sourceText, "Keep every word. Next sentence.")
    }
    func testRevisionInsideCommittedContextDoesNotBlockStableNewWords() async {
        var call = 0
        var texts: [String] = []
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { r in CapturedAudio(samples: Array(repeating: 0.1, count: r.count)) },
            recognize: { _, _ in
                call += 1
                let old = ASRSegment(text: call <= 2 ? "Their house is near the river." : "The house is near the river.", endSample: 32_000)
                let next = ASRSegment(text: " Do not sell it.", endSample: 96_000)
                return ASRResult(text: call <= 2 ? old.text : old.text + next.text, language: .english, processingSeconds: 0,
                    segments: call <= 2 ? [old] : [old, next])
            }, translate: { text, _, _ in texts.append(text); return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [64_000, 96_000, 128_000, 160_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertEqual(texts, ["Their house is near the river.", "Do not sell it."])
        XCTAssertEqual(result.committedSamples, 96_000)
    }
    func testLongBufferKeepsLastSentenceAfterTrimmingOlderContext() async {
        var call = 0; var ranges: [Range<Int>] = []
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { r in ranges.append(r); return CapturedAudio(samples: Array(repeating: 0.1, count: r.count)) },
            recognize: { _, _ in
                call += 1
                let spans: [ASRSegment] = call <= 2
                    ? [.init(text: "First sentence ends here.", endSample: 160_000),
                       .init(text: " Second sentence ends here.", endSample: 320_000),
                       .init(text: " Third sentence has five different words.", endSample: 480_000)]
                    : [.init(text: "Third sentence has five different words.", endSample: 160_000),
                       .init(text: " Fourth sentence.", endSample: 250_000)]
                return ASRResult(text: spans.map(\.text).joined(), language: .english, processingSeconds: 0, segments: spans)
            }, translate: { text, _, _ in TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [600_000, 640_000, 700_000, 750_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertEqual(ranges.map(\.lowerBound), [0, 0, 320_000, 320_000])
        XCTAssertEqual(result.sourceText, "First sentence ends here. Second sentence ends here. Third sentence has five different words. Fourth sentence.")
    }
    func testFinalTailUsesRetainedContextWithoutRetranslatingConfirmedWords() async {
        var calls = 0
        var ranges: [Range<Int>] = []
        var translations: [String] = []
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { r in ranges.append(r); return CapturedAudio(samples: Array(repeating: 0.1, count: r.count)) },
            recognize: { _, _ in
                calls += 1
                let first = ASRSegment(text: "Do not cancel.", endSample: 32_000)
                let tail = ASRSegment(text: " Thank you", endSample: 112_000)
                return ASRResult(text: calls < 3 ? first.text : first.text + tail.text, language: .english, processingSeconds: 0,
                    segments: calls < 3 ? [first] : [first, tail])
            }, translate: { text, _, _ in translations.append(text); return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [64_000, 96_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish(end: 128_000, speechEnd: 120_000)
        XCTAssertEqual(translations, ["Do not cancel.", "Thank you"])
        XCTAssertEqual(ranges.last, 0..<128_000)
        XCTAssertEqual(result.committedSamples, 128_000)
    }
    func testFinalContextOnlyDoesNotSendTinySilenceToAnotherRecognizer() async {
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { r in CapturedAudio(samples: Array(repeating: 0.1, count: r.count)) },
            recognize: { _, _ in ASRResult(text: "Finished.", language: .english, processingSeconds: 0,
                segments: [.init(text: "Finished.", endSample: 32_000)]) },
            translate: { text, _, _ in TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) },
            prepareSpeech: nil, publish: { _ in })
        for end in [64_000, 96_000] { worker.offer(end: end, endsInSilence: false); await worker.waitForIdle() }
        let result = await worker.finish(end: 128_000, speechEnd: 33_000)
        XCTAssertEqual(result.committedSamples, 128_000)
        XCTAssertEqual(result.sourceText, "Finished.")
        XCTAssertEqual(result.blocks, 1)
    }
    func testEllipsisCannotConfirmAnUnfinishedSentence() async {
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in ASRResult(text: "Do not...", language: .english, processingSeconds: 0,
                segments: [.init(text: "Do not...", endSample: 32_000)]) },
            translate: { _, _, _ in XCTFail("An ellipsis is not a completed sentence"); throw PipelineError.inference },
            prepareSpeech: nil, publish: { _ in })
        for end in [64_000, 96_000] { worker.offer(end: end); await worker.waitForIdle() }
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 0)
    }
    func testLongInitialSilenceDoesNotTriggerAnImmediateRecognitionWindow() {
        var policy = RecordingPreviewBoundary()
        for _ in 0..<500 { XCTAssertNil(policy.observe(speech: false, sampleCount: 512)) }
        XCTAssertNil(policy.observe(speech: true, sampleCount: 512))
    }
    func testPollingWithoutTimestampsDoesNotConsumeAnArbitraryCut() async {
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in ASRResult(text: "Artificial ending.", language: .english, processingSeconds: 0) },
            translate: { _, _, _ in XCTFail("Cannot align unfinished audio without timestamps"); throw PipelineError.inference },
            prepareSpeech: nil, publish: { _ in XCTFail("No safe sentence yet") })
        worker.offer(end: 128_000, endsInSilence: false)
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 0)
    }
    func testMalformedTimestampsDoNotDiscardAudio() async {
        let worker = RecordingPreviewCoordinator(source: .english, target: .russian,
            snapshot: { _ in CapturedAudio(samples: [0.1]) },
            recognize: { _, _ in ASRResult(text: "First. Second.", language: .english, processingSeconds: 0,
                segments: [.init(text: "First.", endSample: 32_000), .init(text: " Second.", endSample: 16_000)]) },
            translate: { _, _, _ in XCTFail("Invalid timestamp order"); throw PipelineError.inference },
            prepareSpeech: nil, publish: { _ in XCTFail("No audio may be committed") })
        worker.offer(end: 128_000)
        let result = await worker.finish()
        XCTAssertEqual(result.committedSamples, 0)
    }
    func testContinuousSpeechDoesNotSplitAtClockIntervals() {
        var policy = RecordingPreviewBoundary()
        var ends: [Int] = []
        for _ in 0..<750 {
            if let end = policy.observe(speech: true, sampleCount: 512) { ends.append(end) }
        }
        XCTAssertTrue(ends.isEmpty)
    }
    func testBriefSpeechPauseOffersRecognitionWithoutWaitingForAFullSecond() {
        var policy = RecordingPreviewBoundary()
        for _ in 0..<100 { XCTAssertNil(policy.observe(speech: true, sampleCount: 512)) }
        for _ in 0..<4 { XCTAssertNil(policy.observe(speech: false, sampleCount: 512)) }
        XCTAssertEqual(policy.observe(speech: false, sampleCount: 512), 53_760)
        XCTAssertFalse(policy.endsInSilence, "A short pause alone does not confirm a sentence")
        for _ in 0..<20 { XCTAssertNil(policy.observe(speech: false, sampleCount: 512)) }
    }
    func testSustainedPauseConfirmsOnceWithoutPollingSilenceForever() {
        var policy = RecordingPreviewBoundary()
        for _ in 0..<100 { _ = policy.observe(speech: true, sampleCount: 512) }
        var events: [Bool] = []
        for _ in 0..<500 {
            if policy.observe(speech: false, sampleCount: 512) != nil { events.append(policy.endsInSilence) }
        }
        XCTAssertEqual(events, [false, true])
    }
    func testBoundaryOnlyAfterSpeechAndQuietInterval() {
        var policy = RecordingPreviewBoundary()
        for _ in 0..<100 { XCTAssertNil(policy.observe(speech: false, sampleCount: 512)) }
        for _ in 0..<100 { XCTAssertNil(policy.observe(speech: true, sampleCount: 512)) }
        var boundaries: [Int] = []
        for _ in 0..<100 { if let end = policy.observe(speech: false, sampleCount: 512) { boundaries.append(end) } }
        XCTAssertEqual(boundaries.count, 2)
        XCTAssertTrue(policy.endsInSilence)
        XCTAssertEqual(policy.lastSpeechEnd, 102_400)
        XCTAssertGreaterThan(boundaries[0], policy.lastSpeechEnd)
    }
}
