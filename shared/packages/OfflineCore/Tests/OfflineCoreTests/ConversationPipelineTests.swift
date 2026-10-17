import XCTest
import AVFoundation
@testable import OfflineCore
private actor Calls {
    var items: [String] = []
    func add(_ value: String) { items.append(value) }
    func reset() { items = [] }
}
private actor TestASR: ASRBackend {
    var continuation: CheckedContinuation<Void, Never>?
    var delayed = false
    var sampleCounts: [Int] = []
    func delay() { delayed = true }
    var waiting: Bool { continuation != nil }
    func resolve() { continuation?.resume(); continuation = nil }
    var text = "Не добавляйте сахар"
    func setText(_ value: String) { text = value }
    var detected: SpeechLanguage = .russian
    var detectionError = false
    func detect(_ language: SpeechLanguage) { detected = language }
    func failDetection() { detectionError = true }
    let calls: Calls
    init(_ calls: Calls) { self.calls = calls }
    var loadedURLs: [URL] = []
    func load(modelURL: URL) async throws { loadedURLs.append(modelURL); await calls.add("loadASR") }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        await calls.add(language == nil ? "ASR:auto" : "ASR")
        sampleCounts.append(audio.samples.count)
        if delayed { await withCheckedContinuation { continuation = $0 } }
        if detectionError { throw PipelineError.inference }
        return ASRResult(text: text, language: language ?? detected, processingSeconds: 0.1)
    }
    nonisolated func cancel() {}
    func unload() async { await calls.add("unloadASR") }
}
private actor TestMT: TranslationBackend {
    var translatedInputs: [String] = []
    var progressCallback: (@Sendable (TranslationProgress) -> Void)?
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage, progress: @escaping @Sendable (TranslationProgress) -> Void) async throws -> TranslationResult {
        progressCallback = progress
        return try await translate(text: text, source: source, target: target)
    }
    func emitProgress(_ value: TranslationProgress) { progressCallback?(value) }
    var directions: [String] = []
    var loadedModels: [TranslationModel] = []
    var customText: String?
    func setText(_ text: String) { customText = text }
    let calls: Calls
    var delayed = false
    var continuation: CheckedContinuation<TranslationResult, Error>?
    init(_ calls: Calls) { self.calls = calls }
    func load(modelURL: URL) async throws { await calls.add("loadMT") }
    func load(modelURL: URL, model: TranslationModel) async throws { loadedModels.append(model); try await load(modelURL: modelURL) }
    func delay() { delayed = true }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        translatedInputs.append(text)
        directions.append(source.rawValue + "-" + target.rawValue)
        await calls.add("MT"); if delayed { return try await withCheckedThrowingContinuation { continuation = $0 } }
        if let customText { return TranslationResult(text: customText, firstTokenSeconds: 0.1, processingSeconds: 0.2, fragments: 1) }
        return Self.result
    }
    static var result: TranslationResult { TranslationResult(text: "Do not add sugar", firstTokenSeconds: 0.1, processingSeconds: 0.2, fragments: 1) }
    func resolve() { continuation?.resume(returning: Self.result); continuation = nil }
    var waiting: Bool { continuation != nil }
    nonisolated func cancel() {}
    func unload() async { await calls.add("unloadMT") }
}
private actor TestTTS: SpeechSynthesisBackend {
    var texts: [String] = []
    var delaySecond = false
    var delayFirst = false
    func enableFirstDelay() { delayFirst = true }
    var delayed: CheckedContinuation<SpeechPCM, Error>?
    func enableDelay() { delaySecond = true }
    var waiting: Bool { delayed != nil }
    func resolveDelayed() { delayed?.resume(returning: SpeechPCM(samples: [0.2], sampleRate: 22050)); delayed = nil }
    var second: XCTestExpectation?
    func expectSecond(_ value: XCTestExpectation) { second = value }
    var failingLanguage: SpeechLanguage?
    func fail(_ language: SpeechLanguage?) { failingLanguage = language }
    let calls: Calls
    init(_ calls: Calls) { self.calls = calls }
    func load(directory: URL, language: SpeechLanguage) async throws { await calls.add("loadTTS:" + language.rawValue); if language == failingLanguage { throw PipelineError.modelLoad } }
    func synthesize(text: String) async throws -> SpeechPCM {
        texts.append(text); if texts.count == 2 { second?.fulfill() }
        await calls.add("TTS:" + text)
        if (delaySecond && texts.count == 2) || (delayFirst && texts.count == 1) { return try await withCheckedThrowingContinuation { delayed = $0 } }
        return SpeechPCM(samples: [0.1], sampleRate: 22050)
    }
    nonisolated func cancel() {}
    func unload() async { await calls.add("unloadTTS") }
}
private actor BlockingPreviewArchive: TranslationArchive {
    func saveOriginalRecording(_ audio: URL, text: String, language: SpeechLanguage) -> UUID? { nil }
    func saveOriginalSpeech(text: String, language: SpeechLanguage) -> UUID? { nil }
    let id = UUID()
    var shouldBlock = false
    var continuation: CheckedContinuation<Void, Never>?
    var aborted = false
    var waiting: Bool { continuation != nil }
    func block() { shouldBlock = true }
    func save(original: String, translation: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> UUID? { id }
    func appendAudio(_ pcm: SpeechPCM, to id: UUID) async throws {
        if shouldBlock { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
    func finishAudio(_ id: UUID) async throws {}
    func abortAudio(_ id: UUID) async { aborted = true }
    func copyAudio(_ id: UUID, into directory: URL) async throws -> URL { throw HistoryError.missing }
}
@MainActor private final class TestPlayer: SpeechPlayback {
    let calls: Calls
    init(_ calls: Calls) { self.calls = calls }
    func play(_ pcm: SpeechPCM) async throws { await calls.add("play") }
    func play(file: URL) async throws {
        let audio = try AVAudioFile(forReading: file)
        XCTAssertGreaterThan(audio.length, 0)
        await calls.add("playFile")
    }
    func stop() {}
    func pause() {}
    func resume() {}
    func setRate(_ rate: Float) {}
}
@MainActor private final class BlockingPlayer: SpeechPlayback {
    var continuation: CheckedContinuation<Void, Error>?
    var count = 0
    var pauses = 0, resumes = 0
    var rate: Float = 1
    var lastFile: URL?
    func play(file: URL) async throws {
        lastFile = file
        count = 0
        try await play(SpeechPCM(samples: [0.1], sampleRate: 22050))
    }
    func pause() { pauses += 1 }
    func resume() { resumes += 1 }
    func setRate(_ rate: Float) { self.rate = rate }
    func play(_ pcm: SpeechPCM) async throws {
        count += 1
        if count == 1 { try await withCheckedThrowingContinuation { continuation = $0 } }
    }
    func release() { let c = continuation; continuation = nil; c?.resume() }
    func stop() { let c = continuation; continuation = nil; c?.resume(throwing: CancellationError()) }
}
@MainActor final class ConversationPipelineTests: XCTestCase {
    func testVoiceRecordingIsArchivedWithoutSynthesizingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let calls = Calls(), tts = TestTTS(Calls())
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: tts,
                                            player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        let audio = CapturedAudio(samples: (0..<32000).map { sin(Float($0) * 0.05) * 0.2 })
        await pipeline.runRecording(audio: audio, speechEnd: 24000, source: .russian, target: .english,
                                    speakResult: false, inputMode: "toggle", thermal: "nominal",
                                    stoppedAt: ProcessInfo.processInfo.systemUptime,
                                    requestedPreview: false, fallbackReason: nil)
        let entries = try await TranslationHistory(root: root).list()
        XCTAssertTrue(pipeline.hasOriginalRecording, pipeline.voiceFields.archiveWarning ?? "Missing completed recording")
        XCTAssertNil(pipeline.voiceFields.archiveWarning)
        let original = try XCTUnwrap(entries.first { $0.kind.rawValue == "originalRecording" })
        XCTAssertTrue(original.hasAudio)
        XCTAssertEqual(original.text?.original, "Не добавляйте сахар")
        let url = try await archive.copyAudio(original.id, into: root.appendingPathComponent("share"))
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 2, accuracy: 0.1)
        let synthesized = await tts.texts
        XCTAssertTrue(synthesized.isEmpty, "Sharing the original must use the captured voice, not TTS")
    }
    func testOriginalRecordingPlaysAndSharesWithAudioHistoryDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root.appendingPathComponent("history"))
        await archive.setRecording(text: false, audio: false)
        let calls = Calls(), tts = TestTTS(Calls()), player = BlockingPlayer()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: tts,
                                            player: player, archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english,
                           speakResult: false, inputMode: "toggle", thermal: "nominal",
                           originalRecording: CapturedAudio(samples: Array(repeating: 0.1, count: 32000)))
        XCTAssertTrue(pipeline.hasOriginalRecording)
        let entries = try await archive.list(); XCTAssertTrue(entries.isEmpty)
        let shared = try XCTUnwrap(pipeline.copyOriginalRecording(into: root.appendingPathComponent("share")))
        let data = try Data(contentsOf: shared)
        let audio = try AVAudioFile(forReading: shared)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 2, accuracy: 0.1,
                       "Preserve all microphone audio, not only the tail sent to recognition")
        await pipeline.unload()
        let playback = Task { await pipeline.playOriginalRecording() }
        while player.continuation == nil { await Task.yield() }
        XCTAssertTrue(pipeline.isPlayingOriginalRecording)
        let playing = try XCTUnwrap(player.lastFile)
        XCTAssertEqual(try Data(contentsOf: playing), data)
        pipeline.cancel(); await playback.value
        XCTAssertFalse(pipeline.isBusy); XCTAssertFalse(pipeline.isPlayingOriginalRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playing.path))
        let synthesized = await tts.texts; XCTAssertTrue(synthesized.isEmpty)
        pipeline.clearTemporarySpeech()
        XCTAssertFalse(pipeline.hasOriginalRecording)
        XCTAssertNil(try pipeline.copyOriginalRecording(into: root.appendingPathComponent("after-clear")))
        XCTAssertEqual(try Data(contentsOf: shared), data, "A shared private copy survives clearing the field")
    }
    func testOriginalRecordingRemainsAvailableAfterRecognitionErrorAndClearsWithVoice() async throws {
        let calls = Calls(), asr = TestASR(calls)
        await asr.failDetection()
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.runRecording(audio: CapturedAudio(samples: Array(repeating: 0.1, count: 8000)), speechEnd: 8000,
                                    source: .russian, target: .english, speakResult: false, inputMode: "toggle", thermal: "nominal",
                                    stoppedAt: ProcessInfo.processInfo.systemUptime, requestedPreview: false, fallbackReason: nil)
        XCTAssertNotNil(pipeline.voiceFields.error)
        XCTAssertTrue(pipeline.hasOriginalRecording)
        pipeline.clearFields(in: .text)
        XCTAssertTrue(pipeline.hasOriginalRecording)
        await pipeline.playOriginalRecording()
        let events = await calls.items; XCTAssertTrue(events.contains("playFile"))
        pipeline.clearFields(in: .voice)
        XCTAssertFalse(pipeline.hasOriginalRecording)
    }
    func testQuickTranslationKeepsMainFieldsAndReusesModel() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, speakResult: false, inputMode: "voice", thermal: "nominal")
        await pipeline.run(audio: nil, text: "Основной текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        let voice = pipeline.voiceFields, text = pipeline.textFields
        await pipeline.run(audio: nil, text: "Выделенный текст", source: .russian, speakResult: false, inputMode: "selection", thermal: "nominal", resultMode: .quick)
        XCTAssertEqual(pipeline.quickFields.sourceText, "Выделенный текст")
        XCTAssertFalse(pipeline.quickFields.translatedText.isEmpty)
        XCTAssertEqual(pipeline.textFields.sourceText, text.sourceText)
        XCTAssertEqual(pipeline.textFields.translatedText, text.translatedText)
        XCTAssertEqual(pipeline.voiceFields.sourceText, voice.sourceText)
        pipeline.clearFields(in: .quick)
        XCTAssertTrue(pipeline.quickFields.sourceText.isEmpty)
        XCTAssertEqual(pipeline.textFields.translatedText, text.translatedText)
        let events = await calls.items
        XCTAssertEqual(events.filter { $0 == "loadMT" }.count, 1)
    }
    func testResultTimingSurvivesReplayAndOtherTabButClearsWithItsResult() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, speakResult: false, inputMode: "toggle", thermal: "nominal")
        let voice = try XCTUnwrap(pipeline.voiceFields.timing)
        XCTAssertEqual(voice.recognitionSeconds, 0.1)
        XCTAssertEqual(voice.translationSeconds, 0.2)
        XCTAssertEqual(voice.totalSeconds, 0.3, accuracy: 0.000001)
        await pipeline.run(audio: nil, text: "Без сахара", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        let text = try XCTUnwrap(pipeline.textFields.timing)
        XCTAssertNil(text.recognitionSeconds)
        XCTAssertEqual(text.translationSeconds, 0.2)
        await pipeline.replay(mode: .voice)
        XCTAssertEqual(pipeline.voiceFields.timing, voice)
        XCTAssertEqual(pipeline.textFields.timing, text)
        pipeline.clearFields(in: .voice)
        XCTAssertNil(pipeline.voiceFields.timing)
        XCTAssertEqual(pipeline.textFields.timing, text)
        pipeline.clearFields(in: .text)
        XCTAssertNil(pipeline.textFields.timing)
    }
    func testNewOrCancelledTranslationCannotShowPreviousTiming() async throws {
        let calls = Calls(), mt = TestMT(Calls())
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "Первый текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNotNil(pipeline.textFields.timing)
        await mt.delay()
        let job = Task { await pipeline.run(audio: nil, text: "Новый текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal") }
        while !(await mt.waiting) { await Task.yield() }
        XCTAssertNil(pipeline.textFields.timing)
        pipeline.cancel()
        await mt.resolve(); await job.value
        XCTAssertNil(pipeline.textFields.timing)
        XCTAssertTrue(pipeline.textFields.translatedText.isEmpty)
    }
    func testAutomaticVoiceResultIsAvailableDuringSynthesisPlaybackAndPause() async throws {
        let calls = Calls(), speech = TestTTS(Calls()), player = BlockingPlayer()
        await speech.enableFirstDelay()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: speech, player: player)
        await pipeline.prepare(files, memorySaving: false)
        let job = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian,
            speakResult: true, inputMode: "toggle", thermal: "nominal") }
        defer { pipeline.cancel(); job.cancel() }
        for _ in 0..<1000 {
            if await speech.waiting { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(pipeline.isWaitingForSpeech)
        func assertVisible() {
            let fields = pipeline.fields(for: .voice)
            XCTAssertEqual(fields.timing?.recognitionSeconds, 0.1)
            XCTAssertEqual(fields.timing?.translationSeconds, 0.2, "Timing must be ready before automatic speech finishes")
            XCTAssertEqual(fields.sourceText, "Не добавляйте сахар")
            XCTAssertEqual(fields.translatedText, "Do not add sugar")
            XCTAssertTrue(VoiceResultVisibility.shouldShow(hasOriginal: !fields.sourceText.isEmpty,
                hasTranslation: !fields.translatedText.isEmpty, capturing: false, finishing: true,
                processing: pipeline.isBusy, preview: pipeline.isRecordingPreview, alreadyShown: false))
        }
        assertVisible()
        await speech.resolveDelayed()
        for _ in 0..<1000 {
            if player.continuation != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotNil(player.continuation)
        XCTAssertTrue(pipeline.isSpeaking)
        assertVisible()
        pipeline.toggleSpeechPause()
        XCTAssertTrue(pipeline.isSpeechPaused)
        assertVisible()
        pipeline.toggleSpeechPause()
        XCTAssertEqual(player.pauses, 1); XCTAssertEqual(player.resumes, 1)
        pipeline.cancel()
        await job.value
        XCTAssertFalse(pipeline.isBusy)
        XCTAssertEqual(pipeline.voiceFields.translatedText, "Do not add sugar")
    }
    func testRepeatTranslationPlaysArchivedAudioWithoutInference() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, inputMode: "fixture", thermal: "nominal")
        let before = try await archive.list()
        XCTAssertTrue(try XCTUnwrap(before.first).hasAudio)
        await calls.reset()
        await pipeline.replay(mode: .voice)
        let events = await calls.items
        XCTAssertEqual(events, ["playFile"], "Replay must not run ASR, translation or speech synthesis")
        let after = try await archive.list()
        XCTAssertEqual(before, after, "Replay must not create duplicate history entries")
        XCTAssertEqual(pipeline.samples.count, 1)
        XCTAssertFalse(pipeline.isWaitingForSpeech)
    }

    func testOriginalSpeechArchivesWithoutTranslationAndReusesItsOwnFile() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await calls.reset()
        await pipeline.readAloud("Hello", language: .english, mode: .text, archiveOriginal: true)
        XCTAssertNil(pipeline.error)
        let originalOnly = try await archive.list()
        XCTAssertEqual(originalOnly.count, 1)
        let original = try XCTUnwrap(originalOnly.first)
        XCTAssertEqual(original.kind, .originalSpeech)
        XCTAssertEqual(original.text?.original, "Hello")
        XCTAssertEqual(original.text?.translation, "")
        XCTAssertTrue(original.hasAudio)
        XCTAssertTrue(pipeline.fields(for: .text).translatedText.isEmpty)
        let originalCalls = await calls.items
        XCTAssertFalse(originalCalls.contains("MT")); XCTAssertFalse(originalCalls.contains("ASR"))
        await calls.reset()
        await pipeline.readAloud("Hello", language: .english, mode: .text, archiveOriginal: true)
        let replay = await calls.items; XCTAssertEqual(replay, ["playFile"])
        let same = try await archive.list(); XCTAssertEqual(same, originalOnly)
        // Creating translated speech afterwards must neither overwrite nor lose original audio.
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: true, inputMode: "text", thermal: "nominal")
        let both = try await archive.list()
        XCTAssertEqual(both.count, 2); XCTAssertTrue(both.allSatisfy(\.hasAudio))
        XCTAssertEqual(both.first(where: { $0.id == original.id }), original)
        await calls.reset()
        await pipeline.readAloud("Hello", language: .english, mode: .text, archiveOriginal: true)
        await pipeline.replay(mode: .text)
        let afterBoth = await calls.items; XCTAssertEqual(afterBoth, ["playFile", "playFile"])
    }

    func testFirstManualSpeechSavesAudioForNextReplay() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        let before = try await archive.list()
        let entry = try XCTUnwrap(before.first)
        XCTAssertFalse(entry.hasAudio)
        await pipeline.readAloud(pipeline.translatedText, language: .english, mode: .text)
        let entries = try await archive.list()
        XCTAssertEqual(entries.count, 1)
        let saved = try XCTUnwrap(entries.first)
        XCTAssertTrue(saved.hasAudio)
        XCTAssertEqual(saved.id, entry.id)
        XCTAssertEqual(saved.text, entry.text)
        let reloaded = try await TranslationHistory(root: root).list()
        XCTAssertEqual(reloaded, entries, "Manual audio must survive reopening history")
        await calls.reset()
        await pipeline.replay(mode: .text)
        let events = await calls.items
        XCTAssertEqual(events, ["playFile"])
        let afterReplay = try await archive.list()
        XCTAssertEqual(afterReplay, entries, "No duplicate entry on repeated playback")
    }
    func testTextSharingKeepsOriginalAndTranslationAudioWithoutHistory() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        await pipeline.prepare(files, memorySaving: false)
        let none = try await pipeline.copyTextSpeechForSharing(text: "Hello", language: .english, original: true, into: root.appendingPathComponent("none"))
        XCTAssertNil(none)
        await pipeline.readAloud("Hello", language: .english, mode: .text, archiveOriginal: true)
        let original = try await pipeline.copyTextSpeechForSharing(text: "Hello", language: .english, original: true, into: root.appendingPathComponent("original"))
        let originalURL = try XCTUnwrap(original)
        XCTAssertGreaterThan(try AVAudioFile(forReading: originalURL).length, 0)
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: true, inputMode: "text", thermal: "nominal")
        let translated = pipeline.textFields.translatedText
        let output = try await pipeline.copyTextSpeechForSharing(text: translated, language: .english, original: false, into: root.appendingPathComponent("translation"))
        let outputURL = try XCTUnwrap(output)
        XCTAssertGreaterThan(try AVAudioFile(forReading: outputURL).length, 0)
        await calls.reset()
        let stillOriginal = try await pipeline.copyTextSpeechForSharing(text: "Hello", language: .english, original: true, into: root.appendingPathComponent("original-again"))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(stillOriginal)), try Data(contentsOf: originalURL))
        let stale = try await pipeline.copyTextSpeechForSharing(text: "Changed text", language: .english, original: true, into: root.appendingPathComponent("changed"))
        let wrongLanguage = try await pipeline.copyTextSpeechForSharing(text: translated, language: .russian, original: false, into: root.appendingPathComponent("wrong-language"))
        XCTAssertNil(stale); XCTAssertNil(wrongLanguage)
        let events = await calls.items; XCTAssertTrue(events.isEmpty, "Sharing must never synthesize or replay")
        pipeline.clearFields(in: .text)
        let cleared = try await pipeline.copyTextSpeechForSharing(text: translated, language: .english, original: false, into: root.appendingPathComponent("cleared"))
        XCTAssertNil(cleared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "A private export must survive clearing the fields")
    }
    func testVoiceTranslationSharingWithoutHistoryAndAcrossTabs() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { pipeline.clearTemporarySpeech(); try? FileManager.default.removeItem(at: root) }
        await pipeline.prepare(files, memorySaving: false)
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech)
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: true,
            inputMode: "fixture", thermal: "nominal", resultMode: .voice)
        XCTAssertNil(pipeline.voiceFields.lastHistoryID)
        XCTAssertTrue(pipeline.hasVoiceTranslationSpeech)
        let url = try XCTUnwrap(pipeline.copyVoiceTranslationSpeech(into: root.appendingPathComponent("first")))
        XCTAssertGreaterThan(try AVAudioFile(forReading: url).length, 0)
        await pipeline.readAloud("Other tab", language: .english, mode: .text)
        pipeline.clearFields(in: .text)
        await calls.reset()
        let again = try XCTUnwrap(pipeline.copyVoiceTranslationSpeech(into: root.appendingPathComponent("again")))
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: again))
        let events = await calls.items
        XCTAssertTrue(events.isEmpty, "Sharing must not synthesize or play audio")
        pipeline.clearFields(in: .voice)
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech)
        XCTAssertNil(try pipeline.copyVoiceTranslationSpeech(into: root.appendingPathComponent("cleared")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await pipeline.run(audio: nil, text: "новый текст", source: .russian, speakResult: false,
            inputMode: "fixture", thermal: "nominal", resultMode: .voice)
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech)
        await pipeline.replay(mode: .voice)
        XCTAssertTrue(pipeline.hasVoiceTranslationSpeech)
        pipeline.clearTemporarySpeech()
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech)
    }
    func testVoiceShareIncludesAlreadyPlayedPreviewPrefix() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { pipeline.clearTemporarySpeech(); try? FileManager.default.removeItem(at: root) }
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.readAloud("Warmup", language: .english, mode: .text)
        var prefix = RecordingPreviewResult()
        prefix.source = .russian; prefix.target = .english
        prefix.sourceText = "Первая фраза."; prefix.translatedText = "First sentence."
        prefix.firstSpeech = RecordingPreviewSpeech(text: "First sentence.",
            pcm: SpeechPCM(samples: Array(repeating: 0.1, count: 22050), sampleRate: 22050), seconds: 0.1)
        await pipeline.run(audio: CapturedAudio(samples: []), source: .russian, target: .english, speakResult: true,
            inputMode: "fixture", thermal: "nominal", preview: prefix, resultMode: .voice)
        XCTAssertTrue(pipeline.hasVoiceTranslationSpeech)
        let file = try AVAudioFile(forReading: XCTUnwrap(pipeline.copyVoiceTranslationSpeech(into: root)))
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 1, accuracy: 0.1,
            "An already played prefix must be included even when no speech remains")
        await pipeline.run(audio: nil, text: "Первая фраза.", source: .russian, target: .english, speakResult: false,
            inputMode: "fixture", thermal: "nominal", resultMode: .voice)
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech, "A new recording must not expose the previous audio")
    }
    func testCancelledVoiceTranslationCannotSharePartialAudio() async throws {
        let calls = Calls(), player = BlockingPlayer()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: player)
        await pipeline.prepare(files, memorySaving: false)
        let work = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: true,
            inputMode: "fixture", thermal: "nominal", resultMode: .voice) }
        for _ in 0..<200 where player.continuation == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(player.continuation)
        pipeline.cancel(); await work.value
        XCTAssertFalse(pipeline.hasVoiceTranslationSpeech)
    }
    func testCancelledTextSpeechDoesNotExposePartialAudio() async throws {
        let calls = Calls(), tts = TestTTS(Calls())
        let player = BlockingPlayer()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: tts, player: player)
        await pipeline.prepare(files, memorySaving: false)
        let work = Task { await pipeline.readAloud("Hello", language: .english, mode: .text, archiveOriginal: true) }
        for _ in 0..<200 where player.continuation == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(player.continuation)
        pipeline.cancel(); await work.value
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let incomplete = try await pipeline.copyTextSpeechForSharing(text: "Hello", language: .english, original: true, into: root)
        XCTAssertNil(incomplete)
    }
    func testAutomaticTextSpeechSavesAudioInSameHistoryEntry() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: true, inputMode: "text", thermal: "nominal")
        let entries = try await archive.list()
        XCTAssertEqual(entries.count, 1)
        let saved = try XCTUnwrap(entries.first)
        XCTAssertEqual(saved.id, pipeline.fields(for: .text).lastHistoryID)
        XCTAssertTrue(saved.hasAudio)
        let reloaded = try await TranslationHistory(root: root).list()
        XCTAssertEqual(reloaded, entries)
        await calls.reset()
        await pipeline.replay(mode: .text)
        let events = await calls.items
        XCTAssertEqual(events, ["playFile"])
    }
    func testArchivedReplayVoiceChangesAndMissingFilesRegenerateOnlySpeech() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal")
        // An edited source must never overwrite the translated recording.
        await pipeline.readAloud("Другой текст", language: .russian, mode: .text)
        await calls.reset()
        await pipeline.replay(mode: .text)
        let cached = await calls.items
        XCTAssertEqual(cached, ["playFile"])
        var voices = files.voices
        voices[.english] = URL(fileURLWithPath: "/different-voice")
        await pipeline.updateVoices(voices)
        await calls.reset()
        await pipeline.replay(mode: .text)
        let changed = await calls.items
        XCTAssertEqual(changed, ["loadTTS:en", "TTS:Do not add sugar", "play"])
        let id = try XCTUnwrap(pipeline.lastHistoryID)
        try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString + ".m4a"))
        await calls.reset()
        await pipeline.replay(mode: .text)
        let missing = await calls.items
        XCTAssertEqual(missing, ["TTS:Do not add sugar", "play"])
        XCTAssertNil(pipeline.error)
    }

    func testArchivedReplayPauseSpeedCancellationAndCleanup() async throws {
        let calls = Calls(), player = BlockingPlayer()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: player, archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        let initial = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal") }
        while player.continuation == nil { await Task.yield() }
        player.release(); await initial.value
        await calls.reset()
        let replay = Task { await pipeline.replay(mode: .text) }
        while player.continuation == nil { await Task.yield() }
        XCTAssertTrue(pipeline.isSpeaking)
        XCTAssertFalse(pipeline.isWaitingForSpeech, "A cached replay must not show the wizard")
        let file = try XCTUnwrap(player.lastFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        pipeline.toggleSpeechPause()
        XCTAssertTrue(pipeline.isSpeechPaused)
        pipeline.setPlaybackSpeed(.normal.next)
        XCTAssertEqual(player.rate, Float(PlaybackSpeed.normal.next.rawValue))
        pipeline.toggleSpeechPause()
        XCTAssertFalse(pipeline.isSpeechPaused)
        pipeline.cancel(); await replay.value
        XCTAssertFalse(pipeline.isBusy)
        XCTAssertFalse(pipeline.isSpeaking)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let events = await calls.items
        XCTAssertTrue(events.isEmpty)
        let entries = try await archive.list()
        XCTAssertTrue(try XCTUnwrap(entries.first).hasAudio, "Stopping replay must preserve the original")
    }

    func testRecordingEntrypointKeepsAutomaticLanguage() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.runRecording(audio: CapturedAudio(samples: [0.1]), speechEnd: 1, source: nil, target: .english,
            speakResult: false, inputMode: "fixture", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: false, fallbackReason: nil)
        let items = await calls.items
        XCTAssertTrue(items.contains("ASR:auto"))
        XCTAssertEqual(pipeline.samples.last?.languageMode, "auto")
    }
    func testAutomaticClassicRoutingSurvivesVoiceRefresh() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let classic = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let ultra = URL(fileURLWithPath: "/asr-parakeet-ultra", isDirectory: true)
        await pipeline.prepare(PipelineFiles(asr: classic, translation: files.translation, voices: [:], translationModel: .index9B, ultra: ultra), memorySaving: false)
        XCTAssertTrue(pipeline.isReady)
        await pipeline.preloadRecognition(source: nil)
        let preloaded = await asr.loadedURLs
        XCTAssertEqual(preloaded, [classic])
        await pipeline.updateVoices([.english: classic])
        await pipeline.preloadRecognition(source: .thai)
        let switched = await asr.loadedURLs
        XCTAssertEqual(switched, [classic])
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english, speakResult: false, inputMode: "test", thermal: "nominal")
        let restored = await asr.loadedURLs
        XCTAssertEqual(restored, [classic])
        XCTAssertNil(pipeline.error)
        await pipeline.updateRecognitionFiles(asr: classic, ultra: nil, omnilingual: nil)
        await pipeline.preloadRecognition(source: .russian)
        let fallback = await asr.loadedURLs
        XCTAssertEqual(fallback.last, classic, "Missing Ultra must fall back without changing the language")
    }
    func testManualRecognizerSurvivesVoiceAndPackageRefreshAndSwitchesBack() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let classic = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let ultra = URL(fileURLWithPath: "/" + RecognitionCatalog.ultraID)
        await pipeline.prepare(PipelineFiles(asr: classic, translation: files.translation, voices: [:], translationModel: .index9B, ultra: ultra), memorySaving: false)
        await pipeline.updateRecognitionFiles(asr: classic, ultra: ultra, omnilingual: nil, preference: .whisper)
        await pipeline.preloadRecognition(source: .russian)
        await pipeline.updateVoices([.english: classic])
        await pipeline.updateRecognitionPackage(URL(fileURLWithPath: "/meta"))
        await pipeline.preloadRecognition(source: nil)
        let loaded = await asr.loadedURLs
        XCTAssertEqual(loaded, [classic, classic])
        await pipeline.updateRecognitionFiles(asr: classic, ultra: ultra, omnilingual: nil, preference: .ultra)
        await pipeline.preloadRecognition(source: .english)
        let restored = await asr.loadedURLs
        XCTAssertEqual(restored.last, ultra)
        XCTAssertNil(pipeline.error)
    }
    func testClassicWhisperPersistsThroughPackageAndVoiceRefresh() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let old = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let ultra = URL(fileURLWithPath: "/" + RecognitionCatalog.ultraID)
        await pipeline.prepare(PipelineFiles(asr: old, translation: files.translation, voices: [:],
            translationModel: .index9B, ultra: ultra, recognitionPreference: .whisper), memorySaving: false)
        await pipeline.preloadRecognition(source: nil)
        await pipeline.updateVoices([.english: old])
        await pipeline.updateRecognitionPackage(URL(fileURLWithPath: "/meta"))
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, target: .english,
            speakResult: false, inputMode: "test", thermal: "nominal")
        let loaded = await asr.loadedURLs
        XCTAssertFalse(loaded.isEmpty)
        XCTAssertTrue(loaded.allSatisfy { $0 == old })
        XCTAssertEqual(pipeline.voiceFields.resolvedSource, .russian)
        XCTAssertEqual(pipeline.voiceFields.resolvedTarget, .english)
        XCTAssertNil(pipeline.error)
    }
    func testVerifiedPreviewWaitsForFullRecognitionThenReusesTranslationAndAudio() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await asr.setText("Не добавляйте сахар.")
        XCTAssertTrue(pipeline.beginRecordingPreview(source: .russian, target: .english, speakResult: true, snapshot: { _ in CapturedAudio(samples: [0.1]) }))
        pipeline.offerRecordingBoundary(32_000)
        while pipeline.voiceFields.translatedText.isEmpty { await Task.yield() }
        // Drain optional speculative TTS before blocking final ASR.
        while !(await calls.items).contains(where: { $0.hasPrefix("TTS:") }) { await Task.yield() }
        await calls.reset(); await asr.delay()
        let task = Task { await pipeline.runRecording(audio: CapturedAudio(samples: Array(repeating: 0.1, count: 48_000)), speechEnd: 16_000,
            source: .russian, target: .english, speakResult: true, inputMode: "fixture", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: true, fallbackReason: nil, verifyPreview: true) }
        while !(await asr.waiting) { await Task.yield() }
        let waitingEvents = await calls.items
        XCTAssertFalse(waitingEvents.contains("play"))
        await asr.resolve(); await task.value
        let events = await calls.items, counts = await asr.sampleCounts
        XCTAssertEqual(counts, [1, 48_000], "Verification must receive full recording including committed audio")
        XCTAssertEqual(events.filter { $0 == "MT" }.count, 0)
        XCTAssertEqual(events.filter { $0.hasPrefix("TTS:") }.count, 0)
        XCTAssertEqual(events.filter { $0 == "play" }.count, 1)
        XCTAssertEqual(pipeline.samples.last?.reusedPreviewBlocks, 1)
        XCTAssertEqual(pipeline.samples.last?.processingMode, "during-recording-verified")
        XCTAssertEqual(pipeline.voiceFields.timing?.recognitionSeconds, 0.2, "Include preview recognition and final verification")
        XCTAssertEqual(pipeline.voiceFields.timing?.translationSeconds, 0.2, "Include reused preview translation without timing it twice")
        XCTAssertEqual(pipeline.voiceFields.sourceText, "Не добавляйте сахар.")
        XCTAssertEqual(pipeline.voiceFields.translatedText, "Do not add sugar")
    }
    func testVerifiedPreviewDiscardsWrongPrefixAndCancellationNeverPlaysIt() async {
        for cancel in [false, true] {
            let calls = Calls(); let asr = TestASR(calls), mt = TestMT(calls), tts = TestTTS(calls)
            let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: tts, player: TestPlayer(calls))
            await pipeline.prepare(files, memorySaving: false)
            await asr.setText("Не добавляйте сахар."); await asr.delay()
            var preview = RecordingPreviewResult()
            preview.source = .russian; preview.target = .english
            preview.sourceText = "Добавляйте сахар."; preview.translatedText = "Add sugar."
            preview.translations = [RecordingPreviewBlock(source: preview.sourceText, translation: preview.translatedText)]
            preview.firstSpeech = RecordingPreviewSpeech(text: "Add sugar.", pcm: SpeechPCM(samples: [0.1], sampleRate: 22050), seconds: 0.1)
            let task = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english,
                inputMode: "fixture", thermal: "nominal", preview: preview, verifyPreview: true) }
            while !(await asr.waiting) { await Task.yield() }
            if cancel { pipeline.cancel() }
            await asr.resolve(); await task.value
            let events = await calls.items
            XCTAssertFalse(events.contains("TTS:Add sugar."))
            if cancel {
                XCTAssertFalse(events.contains("play")); XCTAssertEqual(pipeline.samples.last?.status, "cancelled")
            } else {
                XCTAssertEqual(pipeline.voiceFields.translatedText, "Do not add sugar")
                XCTAssertEqual(pipeline.voiceFields.sourceText, "Не добавляйте сахар.")
                XCTAssertEqual(pipeline.samples.last?.retranslatedParts, 1)
            }
        }
    }
    func testEmptyRegeneratedPartCannotPlayOnlyTheCachedPrefix() async {
        let calls = Calls(); let asr = TestASR(calls), mt = TestMT(calls)
        await asr.setText("Hello. First. Second. Third. Do not pay."); await mt.setText("")
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        var preview = RecordingPreviewResult()
        preview.source = .russian; preview.target = .english
        preview.translations = [RecordingPreviewBlock(source: "Hello. First.", translation: "Cached prefix."),
            RecordingPreviewBlock(source: "Second. Third.", translation: "Middle."),
            RecordingPreviewBlock(source: "Pay.", translation: "Wrong.")]
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english,
            inputMode: "fixture", thermal: "nominal", preview: preview, verifyPreview: true)
        let events = await calls.items
        XCTAssertFalse(events.contains("play"))
        XCTAssertEqual(pipeline.samples.last?.status, "failed")
    }
    func testPreviewFinalizationReusesPrefixAndPreparedAudioWithoutDuplicateHistory() async throws {
        let calls = Calls(); let asr = TestASR(calls); await asr.setText("Не добавляйте сахар.")
        let mt = TestMT(calls), tts = TestTTS(calls)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: tts, player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        XCTAssertTrue(pipeline.beginRecordingPreview(source: .russian, target: .english, speakResult: true,
            snapshot: { range in CapturedAudio(samples: Array(repeating: 0.1, count: range.count)) }))
        pipeline.offerRecordingBoundary(32_000)
        // Finalize immediately: drain must include the pending preview without playing during capture.
        await pipeline.runRecording(audio: CapturedAudio(samples: Array(repeating: 0.1, count: 48_000)), speechEnd: 16_000,
            source: .russian, target: .english, speakResult: true, inputMode: "toggle", thermal: "nominal",
            stoppedAt: ProcessInfo.processInfo.systemUptime, requestedPreview: true, fallbackReason: nil)
        let events = await calls.items
        XCTAssertEqual(events.filter { $0 == "ASR" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "MT" }.count, 1)
        XCTAssertEqual(events.filter { $0.hasPrefix("TTS:") }.count, 1)
        XCTAssertEqual(events.filter { $0 == "play" }.count, 1)
        XCTAssertEqual(pipeline.voiceFields.sourceText, "Не добавляйте сахар.")
        XCTAssertTrue(pipeline.textFields.sourceText.isEmpty)
        XCTAssertEqual(pipeline.samples.last?.processingMode, "during-recording")
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        let entries = try await archive.list()
        XCTAssertEqual(entries.filter { $0.kind == .translation }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .originalRecording }.count, 1)
        let recording = try XCTUnwrap(entries.first { $0.kind == .originalRecording })
        let url = try await archive.copyAudio(recording.id, into: root.appendingPathComponent("share"))
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 3, accuracy: 0.1)
        XCTAssertFalse(pipeline.isBusy); XCTAssertFalse(pipeline.isRecordingPreview)
    }
    func testClearingDuringEarlyAudioArchiveAbortsDraftAfterFieldsAreReset() async {
        let calls = Calls(); let archive = BlockingPreviewArchive()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await pipeline.run(audio: nil, text: "Warmup", source: .russian, target: .english, inputMode: "text", thermal: "nominal")
        await archive.block()
        var prefix = RecordingPreviewResult()
        prefix.source = .russian; prefix.target = .english
        prefix.sourceText = "Первая фраза."; prefix.translatedText = "First sentence."
        prefix.firstSpeech = RecordingPreviewSpeech(text: "First sentence.", pcm: SpeechPCM(samples: [0.1], sampleRate: 22050), seconds: 0.1)
        let job = Task { await pipeline.run(audio: CapturedAudio(samples: []), source: .russian, target: .english, inputMode: "fixture", thermal: "nominal", preview: prefix) }
        while !(await archive.waiting) { await Task.yield() }
        pipeline.clearFields(in: .voice)
        await archive.release(); await job.value
        let aborted = await archive.aborted
        XCTAssertTrue(aborted)
        XCTAssertTrue(pipeline.voiceFields.sourceText.isEmpty)
        XCTAssertEqual(pipeline.samples.last?.status, "cancelled")
    }
    func testPreparedPrefixPlaysWhileFinalTranslationIsStillPending() async {
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls); let tts = TestTTS(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: tts, player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await pipeline.run(audio: nil, text: "Warmup", source: .russian, target: .english, inputMode: "text", thermal: "nominal")
        await calls.reset(); await mt.delay()
        var prefix = RecordingPreviewResult()
        prefix.source = .russian; prefix.target = .english
        prefix.sourceText = "Первая фраза."; prefix.translatedText = "First sentence."
        prefix.firstSpeech = RecordingPreviewSpeech(text: "First sentence.", pcm: SpeechPCM(samples: [0.1], sampleRate: 22050), seconds: 0.1)
        let task = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, target: .english,
            inputMode: "fixture", thermal: "nominal", preview: prefix) }
        while !(await mt.waiting) { await Task.yield() }
        for _ in 0..<30 { await Task.yield() }
        let beforeTail = await calls.items
        XCTAssertEqual(beforeTail.filter { $0 == "play" }.count, 1, "Cached prefix must not wait for the final translation")
        XCTAssertTrue(pipeline.isSpeaking)
        await mt.resolve(); await task.value
        let events = await calls.items
        XCTAssertEqual(events.filter { $0 == "play" }.count, 2)
        XCTAssertFalse(events.contains("TTS:First sentence."), "Cached prefix must not be synthesized twice")
        XCTAssertEqual(pipeline.voiceFields.translatedText, "First sentence. Do not add sugar")
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
    }
    func testCancelPreviewDrainsBeforeNextRequest() async {
        let calls = Calls(); let asr = TestASR(calls); await asr.setText("Hello.")
        let mt = TestMT(calls); await mt.delay()
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: [:], translationModel: .qwen9B), memorySaving: false)
        XCTAssertTrue(pipeline.beginRecordingPreview(source: .russian, target: .english, speakResult: false, snapshot: { _ in CapturedAudio(samples: [0.1]) }))
        pipeline.offerRecordingBoundary(32_000)
        while !(await mt.waiting) { await Task.yield() }
        pipeline.cancel()
        XCTAssertTrue(pipeline.isBusy)
        await mt.resolve()
        for _ in 0..<100 where pipeline.isBusy { await Task.yield() }
        XCTAssertFalse(pipeline.isBusy); XCTAssertFalse(pipeline.isRecordingPreview)
        XCTAssertTrue(pipeline.voiceFields.translatedText.isEmpty)
    }
    func testPreviewUnavailableWithMemorySavingOrOtherRecognizer() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: [:], translationModel: .qwen9B), memorySaving: true)
        XCTAssertEqual(pipeline.recordingPreviewUnavailable(source: .russian), "memory-saving")
        XCTAssertFalse(pipeline.beginRecordingPreview(source: .russian, target: .english, speakResult: false, snapshot: { _ in CapturedAudio(samples: []) }))
    }
    func testLargeModelTextDoesNotLoadASRAndKeepsTranslationWarm() async throws {
        let calls = Calls()
        let backend = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: backend, speech: TestTTS(calls), player: TestPlayer(calls))
        let large = PipelineFiles(asr: files.asr, translation: URL(fileURLWithPath: "/index"), voices: [:], translationModel: .index9B)
        await pipeline.prepare(large, memorySaving: false)
        let prepared = await calls.items
        XCTAssertFalse(prepared.contains("loadASR"))
        await pipeline.run(audio: nil, text: "Привет", source: .russian, target: .english, speakResult: false, inputMode: "text", thermal: "nominal")
        let actual = await calls.items
        XCTAssertEqual(actual, ["loadMT", "MT"])
        let models = await backend.loadedModels
        XCTAssertEqual(models, [.index9B])
        XCTAssertEqual(pipeline.samples.last?.translationModelID, TranslationModel.index9B.rawValue)
        XCTAssertEqual(pipeline.samples.last?.memorySaving, false)
        await pipeline.run(audio: nil, text: "Ещё одна фраза", source: .russian, target: .english, speakResult: false, inputMode: "text", thermal: "nominal")
        let reused = await calls.items
        XCTAssertEqual(reused, ["loadMT", "MT", "MT"])
        XCTAssertNil(pipeline.samples.last?.mtLoadSeconds)
        let inputs = await backend.translatedInputs
        XCTAssertEqual(inputs, ["Привет", "Ещё одна фраза"])
    }
    func testLargeModelVoiceReusesASRTranslationAndTTSAcrossTurns() async {
        let calls = Calls()
        let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        let large = PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B)
        await pipeline.prepare(large, memorySaving: false)
        let audio = CapturedAudio(samples: [0.1, 0.2])
        for _ in 0..<2 {
            await pipeline.run(audio: audio, source: .russian, target: .english, speakResult: true, inputMode: "toggle", thermal: "nominal")
        }
        let actual = await calls.items
        XCTAssertEqual(actual.filter { $0 == "loadMT" }.count, 1)
        XCTAssertEqual(actual.filter { $0 == "loadASR" }.count, 1)
        XCTAssertEqual(actual.filter { $0 == "loadTTS:en" }.count, 1)
        XCTAssertEqual(actual.filter { $0 == "play" }.count, 2)
        XCTAssertFalse(actual.contains("unloadMT"))
        XCTAssertNil(pipeline.samples.last?.mtLoadSeconds)
    }

    func testMemoryPressureReleasesIdleRecognizerWithoutUnpreparingTranslation() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let large = PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B)
        await pipeline.prepare(large, memorySaving: false)
        await pipeline.preloadRecognition(source: .russian)
        await calls.reset()
        let handled = await pipeline.relieveMemoryPressure()
        XCTAssertTrue(handled)
        XCTAssertTrue(pipeline.isReady)
        XCTAssertFalse(pipeline.isBusy)
        let released = await calls.items
        XCTAssertEqual(released, ["unloadASR"])
        await pipeline.run(audio: CapturedAudio(samples: [0.1, 0.2]), source: .russian, target: .english, speakResult: true, inputMode: "toggle", thermal: "nominal")
        let events = await calls.items
        XCTAssertTrue(events.contains("loadASR"))
        XCTAssertFalse(events.contains("loadMT"))
        XCTAssertTrue(events.contains("play"))
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        XCTAssertEqual(pipeline.samples.last?.memorySaving, false)
    }

    func testMemoryPressureWaitsForActiveRecognitionAndCoalescesWarnings() async {
        let calls = Calls(), asr = TestASR(Calls())
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await asr.delay()
        let job = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1, 0.2]), source: .russian, target: .english, speakResult: true, inputMode: "toggle", thermal: "nominal") }
        while !(await asr.waiting) { await Task.yield() }
        let first = await pipeline.relieveMemoryPressure()
        let second = await pipeline.relieveMemoryPressure()
        XCTAssertTrue(first && second)
        let before = await asr.calls.items
        XCTAssertFalse(before.contains("unloadASR"))
        await asr.resolve()
        await job.value
        let after = await asr.calls.items
        XCTAssertEqual(after.filter { $0 == "unloadASR" }.count, 1)
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        XCTAssertTrue(pipeline.isReady)
    }

    func testMemoryPressureDuringTranslationPreservesResultAndPlayback() async {
        let calls = Calls(), mt = TestMT(Calls())
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await mt.delay()
        let job = Task { await pipeline.run(audio: CapturedAudio(samples: [0.1, 0.2]), source: .russian, target: .english, speakResult: true, inputMode: "toggle", thermal: "nominal") }
        while !(await mt.waiting) { await Task.yield() }
        // Schedule recovery while the translation backend is still in flight.
        let pressure = Task { await pipeline.relieveMemoryPressure() }
        await Task.yield()
        await mt.resolve()
        await job.value
        let handled = await pressure.value
        XCTAssertTrue(handled)
        XCTAssertTrue(pipeline.isReady)
        XCTAssertEqual(pipeline.voiceFields.translatedText, "Do not add sugar")
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        let events = await calls.items
        XCTAssertTrue(events.contains("unloadASR"))
        XCTAssertTrue(events.contains("play"))
    }

    func testChangingTranslationFileReleasesOldContextBeforeLoadingNewOne() async {
        let calls = Calls()
        let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await calls.reset()
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: URL(fileURLWithPath: "/another-mt"), voices: [:]), memorySaving: false)
        let actual = await calls.items
        XCTAssertEqual(actual, ["unloadMT", "loadMT"])
    }

    func testRecognitionEngineSwitchKeepsTranslatorWarmAndReusesCurrentRecognizer() async {
        let calls = Calls(), recognition = TestASR(Calls())
        let pipeline = ConversationPipeline(asr: recognition, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let whisper = URL(fileURLWithPath: "/whisper.bin"), omni = URL(fileURLWithPath: "/omni", isDirectory: true)
        await pipeline.prepare(PipelineFiles(asr: whisper, translation: whisper, voices: [:], translationModel: .qwen9B, omnilingual: omni), memorySaving: false)
        await calls.reset()
        for source in [SpeechLanguage.russian, .lang_ban, .lang_ban, .russian] {
            await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: source, target: .english, speakResult: false, inputMode: "toggle", thermal: "nominal")
            XCTAssertNil(pipeline.error)
        }
        let loaded = await recognition.loadedURLs
        XCTAssertEqual(loaded, [whisper, omni, whisper])
        let mt = await calls.items
        XCTAssertEqual(mt, ["MT", "MT", "MT", "MT"])
    }

    func testRecognitionDownloadCanBeAttachedAfterPreparation() async {
        let calls = Calls(), recognition = TestASR(Calls())
        let pipeline = ConversationPipeline(asr: recognition, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let whisper = URL(fileURLWithPath: "/whisper.bin"), omni = URL(fileURLWithPath: "/omni", isDirectory: true)
        await pipeline.prepare(PipelineFiles(asr: whisper, translation: whisper, voices: [:], translationModel: .qwen9B), memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .lang_ban, target: .english, speakResult: false, inputMode: "toggle", thermal: "nominal")
        XCTAssertEqual(pipeline.error, RecognitionError.downloadRequired.localizedDescription)
        await pipeline.updateRecognitionPackage(omni)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .lang_ban, target: .english, speakResult: false, inputMode: "toggle", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        let loaded = await recognition.loadedURLs; XCTAssertEqual(loaded, [omni])
    }

    func testNewTextLanguageCompletesWithoutAttemptingMissingVoice() async throws {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .qwen9B), memorySaving: false)
        await calls.reset()
        await pipeline.run(audio: nil, text: "Hello", source: .english,
                           target: try XCTUnwrap(SpeechLanguage(rawValue: "nrm")), speakResult: true, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertFalse(pipeline.translatedText.isEmpty)
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        XCTAssertEqual(pipeline.speechNotice, "Для этого языка пока доступен перевод без озвучки.")
        let actual = await calls.items
        XCTAssertFalse(actual.contains("play"))
        XCTAssertFalse(actual.contains(where: { $0.hasPrefix("loadTTS:") }))
    }

    func testAllLanguagesLoadTheirVoiceAndSharedPackageStillSwitchesLanguage() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let shared = URL(fileURLWithPath: "/shared-multilingual")
        let voices = Dictionary(uniqueKeysWithValues: SpeechLanguage.allCases.map { ($0, shared) })
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: voices, voiceModelIDs: [.thai: "wayu-prosody"], translationModel: .index9B), memorySaving: false)
        for target in SpeechLanguage.allCases.filter({ TranslationLanguage.details($0).connected(to: .index9B) }) {
            await calls.reset()
            await pipeline.run(audio: nil, text: "Hello", source: target == .english ? .russian : .english, target: target, inputMode: "text", thermal: "nominal")
            XCTAssertNil(pipeline.error, target.rawValue)
            XCTAssertEqual(pipeline.samples.last?.voiceModelID, target == .thai ? "wayu-prosody" : "shared-multilingual")
            let actual = await calls.items
            XCTAssertTrue(actual.contains("loadTTS:" + target.rawValue), target.rawValue)
            XCTAssertTrue(actual.contains("play"), target.rawValue)
        }
        await pipeline.updateVoices([:])
        await calls.reset(); await pipeline.replay()
        XCTAssertNotNil(pipeline.error)
        let afterRemoval = await calls.items
        XCTAssertTrue(afterRemoval.isEmpty, "Removing a shared package must not reuse its cached voice")
    }
    func testNewVoicesDoNotEnableImplicitTargetOutsideRussianEnglish() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "Bonjour", source: .french, inputMode: "text", thermal: "nominal")
        XCTAssertNotNil(pipeline.error)
        let actual = await calls.items
        XCTAssertTrue(actual.isEmpty)
    }
    private let files = PipelineFiles(asr: URL(fileURLWithPath: "/asr"), translation: URL(fileURLWithPath: "/mt"), russianVoice: URL(fileURLWithPath: "/ru"), englishVoice: URL(fileURLWithPath: "/en"))
    func testDisabledHistoryStillTranslatesAndPlaysWithoutArchiveWarnings() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        await archive.setRecording(text: false, audio: false)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "Привет", source: .russian, speakResult: true, inputMode: "text", thermal: "nominal")
        let actual = await calls.items
        XCTAssertTrue(actual.contains("MT")); XCTAssertTrue(actual.contains("play"))
        XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
        XCTAssertNil(pipeline.lastHistoryID); XCTAssertNil(pipeline.archiveWarning); XCTAssertNil(pipeline.error)
        let entries = try await archive.list(); XCTAssertTrue(entries.isEmpty)
    }
    func testExplicitThirdLanguageTargetIsArchivedAndNotSpokenWithWrongVoice() async throws {
        let calls = Calls(); let mt = TestMT(calls)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "Bonjour", source: .french, target: .japanese, inputMode: "text", thermal: "nominal")
        let directions = await mt.directions
        XCTAssertEqual(directions, ["fr-ja"])
        XCTAssertEqual(pipeline.resolvedTarget, .japanese)
        XCTAssertEqual(pipeline.samples.last?.target, .japanese)
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        let entries = try await archive.list()
        XCTAssertEqual(entries.first?.source, .french)
        XCTAssertEqual(entries.first?.target, .japanese)
        let actual = await calls.items
        XCTAssertEqual(actual, ["MT"])
        XCTAssertNil(pipeline.error)
        await pipeline.replay()
        XCTAssertNotNil(pipeline.error)
        let afterReplay = await calls.items
        XCTAssertEqual(afterReplay, ["MT"])
    }
    func testTextTranslationWithoutAnyRecognitionPackage() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: nil, translation: files.translation, voices: [:], translationModel: .index9B), memorySaving: false)
        XCTAssertTrue(pipeline.isReady)
        await pipeline.run(audio: nil, text: "Не добавляйте сахар", source: .russian, target: .english, inputMode: "text", thermal: "nominal")
        XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
        XCTAssertNil(pipeline.error)
        let actual = await calls.items
        XCTAssertFalse(actual.contains("loadASR"))
        XCTAssertTrue(actual.contains("MT"))
    }
    func testUltraOnlyPackageRunsRecognitionTranslationAndSpeech() async {
        let calls = Calls(); let asr = TestASR(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        let ultra = URL(fileURLWithPath: "/models/" + RecognitionCatalog.ultraID)
        await pipeline.prepare(PipelineFiles(asr: nil, translation: files.translation, voices: files.voices, translationModel: .index9B, ultra: ultra, recognitionPreference: .ultra), memorySaving: false)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, inputMode: "toggle", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
        let urls = await asr.loadedURLs
        XCTAssertEqual(urls, [ultra])
        let actual = await calls.items
        XCTAssertTrue(actual.contains("play"))
    }
    func testTranslationWithoutVoiceThenInstallingVoiceEnablesReadback() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, russianVoice: nil, englishVoice: nil), memorySaving: false)
        await calls.reset()
        await pipeline.run(audio: nil, text: "bonjour", source: .french, target: .english, inputMode: "text", thermal: "nominal")
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        XCTAssertNotNil(pipeline.speechNotice)
        var actual = await calls.items
        XCTAssertEqual(actual, ["MT"])
        await pipeline.updateVoices(russian: nil, english: files.englishVoice)
        await calls.reset(); await pipeline.replay()
        actual = await calls.items
        XCTAssertEqual(actual, ["loadTTS:en", "TTS:Do not add sugar", "play"])
    }
    func testExplicitSourceBypassesDetectionForTextAndSpeech() async {
        let calls = Calls(); let asr = TestASR(calls)
        let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: [:], translationModel: .index9B), memorySaving: false)
        await pipeline.run(audio: nil, text: "12345", source: .english, target: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.resolvedSource, .english)
        await asr.detect(.japanese)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .english, target: .russian, speakResult: false, inputMode: "voice", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.resolvedSource, .english)
        let directions = await mt.directions
        XCTAssertEqual(directions, ["en-ru", "en-ru"])
        let events = await calls.items
        XCTAssertTrue(events.contains("ASR"))
        XCTAssertFalse(events.contains("ASR:auto"))
    }
    func testAutomaticUsesSelectedTargetForSpeechAndTextAndHistory() async throws {
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: files.voices, translationModel: .index9B), memorySaving: false)
        await calls.reset(); await asr.detect(.lang_uk)
        await asr.setText("Доброго ранку, де знаходиться вокзал?")
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, target: .russian, speakResult: false, inputMode: "audio-file", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.resolvedSource, .lang_uk); XCTAssertEqual(pipeline.resolvedTarget, .russian)
        await pipeline.run(audio: nil, text: "Hello, where is the railway station?", source: nil, target: .french, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.resolvedTarget, .french)
        let directions = await mt.directions
        XCTAssertEqual(directions, ["uk-ru", "en-fr"])
        let entries = try await archive.list()
        XCTAssertEqual(entries.map(\.target), [.french, .russian])
        XCTAssertEqual(entries.map(\.source), [.english, .lang_uk])
    }
    func testAutomaticSameLanguageKeepsTextWithoutTranslationInference() async {
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        let text = "Здравствуйте, где находится железнодорожный вокзал?"
        await pipeline.run(audio: nil, text: text, source: nil, target: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        XCTAssertEqual(pipeline.translatedText, text)
        XCTAssertEqual(pipeline.textFields.timing?.translationSeconds, 0)
        let events = await calls.items
        XCTAssertTrue(events.isEmpty)
    }
    func testAutomaticModelResolvesAfterSpeechDetectionAndPreservesResolverAcrossVoiceUpdates() async throws {
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls)
        await asr.detect(.german); await asr.setText("Guten Morgen")
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        let automatic = PipelineFiles(asr: files.asr, translation: files.translation, voices: [:], translationModel: .opusBig,
            translationResolver: { source, target in
                XCTAssertEqual(source, .german); XCTAssertEqual(target, .english)
                return TranslationInstallation(model: .index2B, url: URL(fileURLWithPath: "/compact"))
            })
        await pipeline.prepare(automatic, memorySaving: false)
        await pipeline.updateVoices(russian: nil, english: nil)
        await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, target: .english, speakResult: false, inputMode: "voice", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        let models = await mt.loadedModels
        XCTAssertEqual(models, [.opusBig, .index2B])
        let events = await calls.items
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "unloadMT")), try XCTUnwrap(events.firstIndex(of: "loadMT")))
        XCTAssertEqual(pipeline.samples.last?.translationModelID, TranslationModel.index2B.rawValue)
    }
    func testAutomaticModelResolvesAfterTextDetectionAndSwitchesBack() async {
        let calls = Calls(); let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: nil, translation: files.translation, voices: [:], translationModel: .opusBig,
            translationResolver: { source, _ in TranslationInstallation(model: source == .german ? .index2B : .opusBig,
                url: URL(fileURLWithPath: source == .german ? "/compact" : "/opus")) }), memorySaving: false)
        await pipeline.run(audio: nil, text: "Guten Morgen, wo befindet sich der Bahnhof?", source: nil, target: .english, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error); XCTAssertEqual(pipeline.resolvedSource, .german)
        await pipeline.run(audio: nil, text: "Где находится железнодорожный вокзал?", source: nil, target: .english, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        let models = await mt.loadedModels
        XCTAssertEqual(models, [.opusBig, .index2B, .opusBig])
    }
    func testDisablingAutoKeepsThePreparedManualModel() async {
        let calls = Calls(); let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: nil, translation: files.translation, voices: [:], translationModel: .opusBig,
            translationResolver: { _, _ in XCTFail("Manual mode must not resolve another model"); return TranslationInstallation(model: .index2B, url: self.files.translation) }), memorySaving: false)
        pipeline.updateTranslationResolver(nil)
        await pipeline.run(audio: nil, text: "Guten Morgen", source: .german, target: .english, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertEqual(pipeline.error, PipelineError.modelLanguageUnavailable.localizedDescription)
        let models = await mt.loadedModels
        XCTAssertEqual(models, [.opusBig])
    }
    func testAutomaticPreviewResolvesTheDetectedPairAndKeepsItsModelForFinalization() async throws {
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls)
        await asr.detect(.german); await asr.setText("Guten Morgen.")
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(PipelineFiles(asr: files.asr, translation: files.translation, voices: [:], translationModel: .index9B,
            translationResolver: { _, _ in TranslationInstallation(model: .index2B, url: URL(fileURLWithPath: "/compact")) }), memorySaving: false)
        XCTAssertTrue(pipeline.beginRecordingPreview(source: nil, target: .english, speakResult: false, snapshot: { range in CapturedAudio(samples: Array(repeating: 0.1, count: range.count)) }))
        pipeline.offerRecordingBoundary(32_000)
        for _ in 0..<200 where pipeline.voiceFields.translatedText.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(pipeline.voiceFields.translatedText.isEmpty)
        await pipeline.runRecording(audio: CapturedAudio(samples: Array(repeating: 0.1, count: 32_000)), speechEnd: 16_000, source: nil, target: .english,
            speakResult: false, inputMode: "voice", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: true, fallbackReason: nil)
        XCTAssertNil(pipeline.error)
        let models = await mt.loadedModels
        XCTAssertEqual(models, [.index9B, .index2B])
        XCTAssertEqual(pipeline.samples.last?.translationModelID, TranslationModel.index2B.rawValue)
    }
    func testAutomaticUnsupportedModelPairStopsBeforeTranslation() async {
        let calls = Calls(); let asr = TestASR(calls); await asr.detect(.lang_ban)
        let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, target: .russian, speakResult: false, inputMode: "voice", thermal: "nominal")
        XCTAssertEqual(pipeline.error, PipelineError.modelLanguageUnavailable.localizedDescription)
        let events = await calls.items
        XCTAssertEqual(events, ["loadASR", "ASR:auto"])
    }
    func testAutomaticRejectsLanguageOutsideRussianEnglishPair() async {
        let calls = Calls(); let asr = TestASR(calls); await asr.detect(.french)
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, inputMode: "toggle", thermal: "nominal")
        XCTAssertNotNil(pipeline.error)
        let actual = await calls.items
        XCTAssertEqual(actual, ["loadASR", "ASR:auto"])
    }
    func testAudioRunsFullPipelineInOrder() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, inputMode: "hold", thermal: "nominal")
        let actual = await calls.items
        XCTAssertEqual(actual, ["loadASR", "ASR", "MT", "loadTTS:en", "TTS:Do not add sugar", "play"])
        XCTAssertEqual(pipeline.sourceText, "Не добавляйте сахар")
        XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
    }
    func testTypedTextSkipsRecognition() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "Это не мой чемодан", source: .russian, inputMode: "text", thermal: "nominal")
        let actual = await calls.items
        XCTAssertEqual(actual, ["MT", "loadTTS:en", "TTS:Do not add sugar", "play"])
        XCTAssertEqual(pipeline.sourceText, "Это не мой чемодан")
    }
    func testClearingSourceCancelsPendingTranslationWithoutRefillingFields() async {
        let calls = Calls(), mt = TestMT(Calls())
        await mt.delay()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        let running = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal") }
        while !(await mt.waiting) { await Task.yield() }
        pipeline.clearFields(in: .text)
        await mt.resolve(); await running.value
        XCTAssertEqual(pipeline.sourceText, "")
        XCTAssertEqual(pipeline.translatedText, "")
        XCTAssertNil(pipeline.resolvedSource)
        XCTAssertFalse(pipeline.isBusy)
        let actual = await calls.items
        XCTAssertFalse(actual.contains("play"))
    }
    func testClearingBothFieldsPreservesHistoryAndWarmModels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root), calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "Без сахара", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        pipeline.clearFields(in: .text)
        XCTAssertEqual(pipeline.sourceText, "")
        XCTAssertEqual(pipeline.translatedText, "")
        pipeline.clearFields(in: .text)
        XCTAssertEqual(pipeline.translatedText, "")
        XCTAssertNil(pipeline.resolvedTarget)
        XCTAssertNil(pipeline.lastHistoryID)
        XCTAssertTrue(pipeline.isReady)
        let entries = try await archive.list()
        XCTAssertEqual(entries.count, 1)
        await calls.reset(); await pipeline.replay()
        let replay = await calls.items
        XCTAssertTrue(replay.isEmpty)
        await pipeline.run(audio: nil, text: "Новая фраза", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        pipeline.clearFields(in: .text)
        XCTAssertEqual(pipeline.sourceText, "")
        let actual = await calls.items
        XCTAssertEqual(actual, ["MT"])
    }
    func testVoiceAndTextFieldsStayIndependentAndReplayUsesChosenTab() async throws {
        let calls = Calls(), mt = TestMT(Calls()), tts = TestTTS(Calls())
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: tts, player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await mt.setText("Voice result")
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, speakResult: false, inputMode: "toggle", thermal: "nominal")
        XCTAssertEqual(pipeline.fields(for: .voice).translatedText, "Voice result")
        XCTAssertEqual(pipeline.fields(for: .text).translatedText, "")
        await mt.setText("Text result")
        await pipeline.run(audio: nil, text: "Напечатано", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertEqual(pipeline.fields(for: .voice).sourceText, "Не добавляйте сахар")
        XCTAssertEqual(pipeline.fields(for: .voice).translatedText, "Voice result")
        XCTAssertEqual(pipeline.fields(for: .text).sourceText, "Напечатано")
        XCTAssertEqual(pipeline.fields(for: .text).translatedText, "Text result")
        await pipeline.replay(mode: .voice)
        let spoken = await tts.texts
        XCTAssertEqual(spoken, ["Voice result"])
        pipeline.clearFields(in: .voice)
        XCTAssertEqual(pipeline.fields(for: .voice).sourceText, "")
        XCTAssertEqual(pipeline.fields(for: .voice).translatedText, "")
        XCTAssertEqual(pipeline.fields(for: .text).translatedText, "Text result")
        pipeline.clearFields(in: .text)
        XCTAssertEqual(pipeline.fields(for: .text).sourceText, "")
        XCTAssertEqual(pipeline.fields(for: .text).translatedText, "")
    }
    func testCancelledTranslationNeverReachesSpeakerAndUnloadJoins() async {
        let calls = Calls(); let mt = TestMT(calls); await mt.delay()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        let running = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal") }
        while !(await mt.waiting) { await Task.yield() }
        pipeline.cancel()
        await pipeline.run(audio: nil, text: "новый", source: .english, inputMode: "text", thermal: "nominal")
        let freeing = Task { await pipeline.unload() }
        for _ in 0..<50 { await Task.yield() }
        let early = await calls.items
        XCTAssertEqual(early, ["MT"], "Cancelled native calls must drain before freeing models or starting another operation")
        await mt.resolve(); await running.value; await freeing.value
        let final = await calls.items
        XCTAssertFalse(final.contains("play")); XCTAssertTrue(final.contains("unloadMT"))
        XCTAssertEqual(pipeline.translatedText, ""); XCTAssertFalse(pipeline.isReady)
        XCTAssertEqual(pipeline.samples.last?.status, "cancelled")
    }
    func testMemorySavingUnloadsBeforeLoadingNextHeavyModel() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: true); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .english, inputMode: "toggle", thermal: "nominal")
        let actual = await calls.items
        XCTAssertEqual(actual, ["loadASR", "ASR", "unloadASR", "loadMT", "MT", "unloadMT", "loadTTS:ru", "TTS:Do not add sugar", "play"])
    }

    func testFailedVoiceSwitchReloadsOriginalVoice() async {
        let calls = Calls(); let tts = TestTTS(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: tts, player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal")
        await tts.fail(.russian)
        await pipeline.run(audio: nil, text: "text", source: .english, inputMode: "text", thermal: "nominal")
        XCTAssertNotNil(pipeline.error)
        await tts.fail(nil); await calls.reset()
        await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal")
        let actual = await calls.items
        XCTAssertEqual(actual, ["MT", "loadTTS:en", "TTS:Do not add sugar", "play"])
    }

    func testNextSpeechIsPreparedDuringPlaybackAndQueueIsBounded() async {
        let calls = Calls(); let mt = TestMT(calls); let tts = TestTTS(calls); let player = BlockingPlayer()
        await mt.setText(String(repeating: "Another short sentence. ", count: 20))
        let second = expectation(description: "Second PCM while first playback is blocked")
        await tts.expectSecond(second)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: tts, player: player)
        await pipeline.prepare(files, memorySaving: false)
        let job = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal") }
        await fulfillment(of: [second], timeout: 3)
        let buffered = await tts.texts
        XCTAssertEqual(buffered.count, 2)
        XCTAssertLessThanOrEqual(buffered.first?.count ?? 1000, 90)
        XCTAssertEqual(player.count, 1)
        player.release(); await job.value
        let all = await tts.texts
        XCTAssertEqual(all.joined(separator: " "), String(repeating: "Another short sentence. ", count: 20).trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(player.count, all.count)
    }

    func testCancelJoinsPrefetchAndDiscardsIncompleteAudio() async throws {
        let calls = Calls(); let mt = TestMT(calls); let tts = TestTTS(calls); let player = BlockingPlayer()
        await mt.setText(String(repeating: "Another sentence. ", count: 20)); await tts.enableDelay()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: tts, player: player, archive: archive)
        await pipeline.prepare(files, memorySaving: false)
        let job = Task { await pipeline.run(audio: nil, text: "текст", source: .russian, inputMode: "text", thermal: "nominal") }
        while !(await tts.waiting) { await Task.yield() }
        pipeline.cancel()
        let unload = Task { await pipeline.unload() }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(pipeline.isBusy)
        let before = await calls.items; XCTAssertFalse(before.contains("unloadTTS"))
        await tts.resolveDelayed(); await job.value; await unload.value
        let entries = try await archive.list()
        XCTAssertEqual(entries.count, 1); XCTAssertNotNil(entries.first?.text); XCTAssertFalse(entries.first?.hasAudio ?? true)
        XCTAssertEqual(player.count, 1)
        XCTAssertEqual(pipeline.samples.last?.status, "cancelled")
    }

    func testAutomaticSpeechRoutesEachReplyAndArchivesActualDirection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let calls = Calls(); let asr = TestASR(calls); let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: asr, translator: mt, speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await asr.detect(.english)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, inputMode: "toggle", thermal: "nominal")
        await asr.detect(.russian)
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, inputMode: "toggle", thermal: "nominal")
        let actual = await calls.items; let directions = await mt.directions
        XCTAssertEqual(actual.filter { $0.hasPrefix("ASR") }, ["ASR:auto", "ASR:auto"])
        XCTAssertEqual(directions, ["en-ru", "ru-en"])
        XCTAssertEqual(actual.filter { $0.hasPrefix("loadTTS") }, ["loadTTS:ru", "loadTTS:en"])
        XCTAssertEqual(pipeline.samples.map(\.source), [.english, .russian])
        XCTAssertEqual(pipeline.samples.map(\.voiceModelID), ["ru", "en"])
        let entries = try await archive.list()
        XCTAssertEqual(entries.map(\.source), [.russian, .english])
        XCTAssertTrue(entries.allSatisfy(\.hasAudio))
    }
    func testFailedDetectionDoesNotTranslateOrCreateHistory() async throws {
        let calls = Calls(); let asr = TestASR(calls); await asr.failDetection()
        let pipeline = ConversationPipeline(asr: asr, translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: nil, inputMode: "toggle", thermal: "nominal")
        let actual = await calls.items
        XCTAssertFalse(actual.contains("MT")); XCTAssertFalse(actual.contains("play"))
        XCTAssertNil(pipeline.lastHistoryID); XCTAssertNotNil(pipeline.error)
        XCTAssertNil(pipeline.samples.last?.source)
        XCTAssertNil(pipeline.samples.last?.voiceModelID)
    }
    func testAutomaticTextUsesOppositeLanguageInBothDirectionsWithoutASR() async {
        let calls = Calls()
        let mt = TestMT(calls)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "Hello, where is the railway station?", source: nil, speakResult: false, inputMode: "text", thermal: "nominal")
        await pipeline.run(audio: nil, text: "Здравствуйте, где находится железнодорожный вокзал?", source: nil, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error)
        let directions = await mt.directions
        XCTAssertEqual(directions, ["en-ru", "ru-en"])
        XCTAssertEqual(pipeline.samples.map(\.languageMode), ["auto", "auto"])
        let actual = await calls.items
        XCTAssertEqual(actual, ["MT", "MT"])
        await calls.reset()
        await pipeline.run(audio: nil, text: "12345", source: nil, inputMode: "text", thermal: "nominal")
        XCTAssertNotNil(pipeline.error)
        let unknown = await calls.items
        XCTAssertTrue(unknown.isEmpty)
    }
    func testPauseResumeAndRateDoNotRegenerateSpeechAndCancelClearsPause() async {
        let calls = Calls(); let player = BlockingPlayer()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: player)
        await pipeline.prepare(files, memorySaving: false)
        let read = Task { await pipeline.readAloud("Hello", language: .english) }
        while player.continuation == nil { await Task.yield() }
        pipeline.toggleSpeechPause()
        XCTAssertTrue(pipeline.isSpeechPaused)
        XCTAssertTrue(pipeline.isSpeaking)
        XCTAssertTrue(pipeline.isBusy)
        pipeline.setPlaybackSpeed(.oneAndHalf)
        XCTAssertEqual(pipeline.playbackSpeed.rawValue, 1.5)
        XCTAssertEqual(player.rate, 1.5)
        XCTAssertEqual(player.pauses, 1)
        pipeline.toggleSpeechPause()
        XCTAssertFalse(pipeline.isSpeechPaused)
        XCTAssertEqual(player.resumes, 1)
        XCTAssertEqual(player.count, 1, "Resume must not start PCM from the beginning")
        pipeline.toggleSpeechPause()
        pipeline.cancel(); await read.value
        XCTAssertFalse(pipeline.isSpeechPaused)
        XCTAssertFalse(pipeline.isSpeaking)
        XCTAssertFalse(pipeline.isBusy)
        let actual = await calls.items
        XCTAssertEqual(actual.filter { $0.hasPrefix("TTS:") }, ["TTS:Hello"])
        pipeline.toggleSpeechPause()
        XCTAssertFalse(pipeline.isSpeechPaused, "Idle playback cannot be paused")
    }

    func testSpeechWaitingIndicatorEndsAtPlaybackAndResetsOnCancellation() async throws {
        for cancelWhileWaiting in [false, true] {
            let calls = Calls(), speech = TestTTS(Calls()), player = BlockingPlayer()
            await speech.enableFirstDelay()
            let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: speech, player: player)
            await pipeline.prepare(files, memorySaving: false)
            let read = Task { await pipeline.readAloud("Hello", language: .english) }
            for _ in 0..<1000 {
                if await speech.waiting { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            let waiting = await speech.waiting
            XCTAssertTrue(waiting)
            XCTAssertTrue(pipeline.isWaitingForSpeech)
            if cancelWhileWaiting { pipeline.cancel() }
            await speech.resolveDelayed()
            if !cancelWhileWaiting {
                for _ in 0..<1000 {
                    if player.continuation != nil { break }
                    try await Task.sleep(for: .milliseconds(1))
                }
                XCTAssertNotNil(player.continuation)
                XCTAssertTrue(pipeline.isSpeaking)
                XCTAssertFalse(pipeline.isWaitingForSpeech)
                pipeline.cancel()
            }
            await read.value
            XCTAssertFalse(pipeline.isBusy)
            XCTAssertFalse(pipeline.isWaitingForSpeech)
        }
    }

    func testSpeechStateRemainsStoppableDuringPlaybackAndClearsAfterCancel() async {
        let calls = Calls(); let player = BlockingPlayer()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: player)
        await pipeline.prepare(files, memorySaving: false)
        let read = Task { await pipeline.readAloud("Hello", language: .english) }
        while player.continuation == nil { await Task.yield() }
        XCTAssertTrue(pipeline.isSpeaking)
        pipeline.cancel(); await read.value
        XCTAssertFalse(pipeline.isSpeaking); XCTAssertFalse(pipeline.isBusy)
    }

    func testLargeTextProgressRejectsLateEventsAndClearsOnCancel() async {
        let calls = Calls(); let mt = TestMT(calls); await mt.delay()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        let run = Task { await pipeline.run(audio: nil, text: String(repeating: "я", count: 1500), source: .russian, speakResult: false, inputMode: "text", thermal: "nominal") }
        while !(await mt.waiting) { await Task.yield() }
        var work = TranslationWork(pieces: [String(repeating: "я", count: 500), String(repeating: "я", count: 1000)])
        let old = work.progress
        work.completeCurrent(); await mt.emitProgress(work.progress)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(pipeline.translationProgress?.completedCharacters, 500)
        await mt.emitProgress(old)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(pipeline.translationProgress?.completedCharacters, 500, "Out-of-order events must not rewind the bar")
        pipeline.cancel()
        await mt.emitProgress(work.progress)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(pipeline.translationProgress)
        await mt.resolve(); await run.value
        XCTAssertNil(pipeline.translationProgress)
        XCTAssertTrue(pipeline.translatedText.isEmpty)
    }

    func testProgressThresholdAndCompletionCleanup() async {
        for count in [999, 1000] {
            let calls = Calls(); let mt = TestMT(calls); await mt.delay()
            let pipeline = ConversationPipeline(asr: TestASR(calls), translator: mt, speech: TestTTS(calls), player: TestPlayer(calls))
            await pipeline.prepare(files, memorySaving: false)
            let run = Task { await pipeline.run(audio: nil, text: String(repeating: "я", count: count), source: .russian, speakResult: false, inputMode: "text", thermal: "nominal") }
            while !(await mt.waiting) { await Task.yield() }
            XCTAssertEqual(pipeline.translationProgress != nil, count == 1000)
            await mt.resolve(); await run.value
            XCTAssertNil(pipeline.translationProgress)
            XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
        }
    }

    func testTextOnlySavesTextAndSpeaksOnlyWhenRequested() async throws {
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls), archive: archive)
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        let before = await calls.items
        XCTAssertEqual(before, ["MT"])
        let entries = try await archive.list()
        XCTAssertEqual(entries.first?.text?.translation, "Do not add sugar")
        XCTAssertFalse(entries.first?.hasAudio ?? true)
        XCTAssertEqual(pipeline.samples.last?.status, "completed")
        await pipeline.replay()
        let after = await calls.items
        XCTAssertEqual(after, ["MT", "loadTTS:en", "TTS:Do not add sugar", "play"])
    }

    func testSpeechCanTranslateSilentlyThenPlayOnRequest() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.run(audio: CapturedAudio(samples: [0.1]), source: .russian, speakResult: false, inputMode: "hold", thermal: "nominal")
        let before = await calls.items
        XCTAssertTrue(before.contains("MT")); XCTAssertFalse(before.contains("play"))
        XCTAssertFalse(before.contains(where: { $0.hasPrefix("TTS:") }))
        await pipeline.replay()
        let after = await calls.items
        XCTAssertEqual(after.filter { $0 == "MT" }.count, 1); XCTAssertTrue(after.contains("play"))
    }

    func testOriginalSpeechUsesCurrentInputAndDoesNotReplaceTranslation() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "текст", source: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        await calls.reset()
        await pipeline.readAloud("Изменённый оригинал", language: .russian)
        let originalCalls = await calls.items
        XCTAssertEqual(originalCalls, ["loadTTS:ru", "TTS:Изменённый оригинал", "play"])
        XCTAssertEqual(pipeline.sourceText, "текст")
        XCTAssertEqual(pipeline.translatedText, "Do not add sugar")
        await pipeline.replay()
        let allCalls = await calls.items
        XCTAssertEqual(allCalls.suffix(3), ["loadTTS:en", "TTS:Do not add sugar", "play"])
        XCTAssertFalse(allCalls.contains("MT"))
        XCTAssertEqual(pipeline.samples.count, 1)
    }
    func testOriginalCanBeReadBeforeAnyTranslation() async {
        let calls = Calls()
        let pipeline = ConversationPipeline(asr: TestASR(calls), translator: TestMT(calls), speech: TestTTS(calls), player: TestPlayer(calls))
        await pipeline.prepare(files, memorySaving: false); await calls.reset()
        await pipeline.readAloud("Hello", language: .english)
        await pipeline.readAloud("  ", language: .russian)
        let actual = await calls.items
        XCTAssertEqual(actual, ["loadTTS:en", "TTS:Hello", "play"])
        XCTAssertTrue(pipeline.translatedText.isEmpty); XCTAssertTrue(pipeline.samples.isEmpty)
    }

}
