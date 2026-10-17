import XCTest
import AVFoundation
import OfflineCore
@testable import Kat_translator

private actor SpeechEvents {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
    var playCount: Int { values.filter { $0 == "play" }.count }
}
private actor UnusedRecognition: ASRBackend {
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult { throw PipelineError.inference }
    nonisolated func cancel() {}
    func unload() async {}
}
/// Deliberately scripted translation isolates the production speech pipeline from model wording.
private actor SpeechFixtureTranslation: TranslationBackend {
    let text: String, partialText: String
    let events: SpeechEvents
    init(text: String, partial: String, events: SpeechEvents) { self.text = text; partialText = partial; self.events = events }
    func load(modelURL: URL) async throws {}
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        TranslationResult(text: self.text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        let start = ProcessInfo.processInfo.systemUptime
        partial(partialText)
        while await events.playCount < 2 {
            guard ProcessInfo.processInfo.systemUptime - start < 60 else { throw PipelineError.inference }
            try await Task.sleep(for: .milliseconds(10))
        }
        await events.add("translation-finished")
        return TranslationResult(text: self.text, firstTokenSeconds: 0, processingSeconds: ProcessInfo.processInfo.systemUptime - start, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor ObservedIrina: SpeechSynthesisBackend {
    let backend = SherpaSpeechBackend()
    private(set) var inputs: [String] = []
    private(set) var samplesProduced = 0
    func load(directory: URL, language: SpeechLanguage) async throws { try await backend.load(directory: directory, language: language) }
    func synthesize(text: String) async throws -> SpeechPCM {
        inputs.append(text)
        let pcm = try await backend.synthesize(text: text)
        samplesProduced += pcm.samples.count
        return pcm
    }
    nonisolated func cancel() { backend.cancel() }
    func unload() async { await backend.unload() }
}
private actor ObservedMLXTranslation: TranslationBackend {
    let backend = RoutedTranslationBackend()
    let events: SpeechEvents
    init(_ events: SpeechEvents) { self.events = events }
    func load(modelURL: URL) async throws { try await backend.load(modelURL: modelURL, model: .index9B) }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await backend.translate(text: text, source: source, target: target)
    }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage,
                   progress: @escaping @Sendable (TranslationProgress) -> Void,
                   partial: @escaping @Sendable (String) -> Void) async throws -> TranslationResult {
        let result = try await backend.translate(text: text, source: source, target: target, progress: progress, partial: partial)
        await events.add("translation-finished")
        return result
    }
    nonisolated func cancel() { backend.cancel() }
    func unload() async { await backend.unload() }
}
/// Captures exactly the PCM scheduled for playback; no microphone or history is involved.
@MainActor private final class CapturedSpeechPlayer: SpeechPlayback {
    let events: SpeechEvents
    private(set) var samples: [Float] = []
    private(set) var sampleRate = 0
    init(_ events: SpeechEvents) { self.events = events }
    func play(_ pcm: SpeechPCM) async throws {
        XCTAssertTrue(sampleRate == 0 || sampleRate == pcm.sampleRate)
        sampleRate = pcm.sampleRate; samples += pcm.samples
        await events.add("play")
    }
    func play(file: URL) async throws { XCTFail("Unexpected file playback") }
    func stop() {}
    func pause() {}
    func resume() {}
    func setRate(_ rate: Float) {}
}

final class StreamedSpeechIntegrationTests: XCTestCase {
    @MainActor func testDefaultMLXStartsRealSpeechBeforeTranslationCompletes() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KAT_STREAMED_SPEECH_INTEGRATION"] == "1", env["KAT_MLX_INTEGRATION"] == "1" else {
            throw XCTSkip("Opt-in local MLX and Irina synthesis")
        }
        let events = SpeechEvents(), speech = ObservedIrina()
        let player = CapturedSpeechPlayer(events)
        let translator = ObservedMLXTranslation(events)
        let pipeline = ConversationPipeline(asr: UnusedRecognition(), translator: translator, speech: speech, player: player)
        let files = PipelineFiles(asr: nil, translation: URL(fileURLWithPath: try XCTUnwrap(env["KAT_MLX_MODEL_PATH"])),
                                  voices: [.russian: URL(fileURLWithPath: try XCTUnwrap(env["KAT_IRINA_PATH"]))])
        await pipeline.prepare(files, memorySaving: false)
        let input = "The hotel opens at eight in the morning. Breakfast is included in the price. Please leave the keys at reception. The museum is near the railway station. The bus leaves every twenty minutes. We will meet at the entrance tomorrow."
        await pipeline.run(audio: nil, text: input, source: .english, target: .russian,
                           speakResult: true, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error); XCTAssertFalse(pipeline.translatedText.isEmpty)
        let inputs = await speech.inputs
        func words(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        XCTAssertEqual(words(inputs.joined(separator: " ")), words(pipeline.translatedText))
        let order = await events.values
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: "play")), try XCTUnwrap(order.firstIndex(of: "translation-finished")),
                          "Real default Mac MLX must start real voice synthesis/playback scheduling before finishing translation")
        XCTAssertGreaterThan(player.samples.count, player.sampleRate)
        XCTAssertTrue(player.samples.allSatisfy(\.isFinite))
        print("MLX_REAL_SPEECH_OK parts=\(inputs.count) playbackParts=\(order.filter { $0 == "play" }.count) early=true wordsOnce=true")
        await pipeline.unload()
    }
    @MainActor func testRealIrinaRetainsLongSentencesWhitespaceAndOrdinals() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KAT_STREAMED_SPEECH_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in local Irina synthesis") }
        let voice = URL(fileURLWithPath: try XCTUnwrap(env["KAT_IRINA_PATH"]))
        let directory = URL(fileURLWithPath: try XCTUnwrap(env["KAT_STREAMED_SPEECH_OUTPUT"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = "Пожалуйста, подтвердите, что в стоимость номера входит завтрак для каждого гостя и что из окна открывается красивый вид на город."
        let second = "Встречаемся на 1-й улице перед 1-м рейсом."
        let last = "Измените дату с 15-го на 16-е октября. Вспомним 80-е годы."
        let full = first + "\n\t" + second + "  " + last
        XCTAssertGreaterThan(first.count, 90); XCTAssertLessThanOrEqual(first.count, 180)
        let events = SpeechEvents(), speech = ObservedIrina()
        // Share a single event log for ordering, while retaining the actual rendered audio.
        let capture = CapturedSpeechPlayer(events)
        let translator = SpeechFixtureTranslation(text: full, partial: first + "\n\t" + second + "  Измените", events: events)
        let pipeline = ConversationPipeline(asr: UnusedRecognition(), translator: translator, speech: speech, player: capture)
        let files = PipelineFiles(asr: nil, translation: directory, voices: [.russian: voice])
        await pipeline.prepare(files, memorySaving: false)
        await pipeline.run(audio: nil, text: "Please confirm the booking and change the arrival date.", source: .english,
                           target: .russian, speakResult: true, inputMode: "text", thermal: "nominal")
        XCTAssertNil(pipeline.error); XCTAssertEqual(pipeline.translatedText, full)
        let inputs = await speech.inputs
        func words(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        XCTAssertEqual(words(inputs.joined(separator: " ")), words(full), "Every source word must be synthesized once, in order")
        let order = await events.values
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: "play")), try XCTUnwrap(order.firstIndex(of: "translation-finished")))
        XCTAssertEqual(order.filter { $0 == "play" }.count, 3)
        XCTAssertTrue(capture.samples.allSatisfy(\.isFinite)); XCTAssertEqual(capture.sampleRate, 22050)
        let seconds = Double(capture.samples.count) / Double(capture.sampleRate)
        XCTAssertGreaterThan(seconds, 10); XCTAssertLessThan(seconds, 60)
        XCTAssertGreaterThan(capture.samples.map { abs($0) }.max() ?? 0, 0.05)
        let expanded = inputs.map(RussianSpeechText.expandOrdinals).joined(separator: " ")
        for phrase in ["на первой улице", "перед первым рейсом", "с пятнадцатого на шестнадцатое октября", "восьмидесятые годы"] {
            XCTAssertTrue(expanded.contains(phrase), phrase)
        }
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(capture.sampleRate), channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capture.samples.count)))
        buffer.frameLength = buffer.frameCapacity
        capture.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        let file = try AVAudioFile(forWriting: directory.appendingPathComponent("irina-streamed.wav"), settings: format.settings)
        try file.write(from: buffer)
        try expanded.write(to: directory.appendingPathComponent("expected-speech.txt"), atomically: true, encoding: .utf8)
        let summary: [String: Any] = ["seconds": seconds, "sampleRate": capture.sampleRate, "synthesisParts": inputs.count,
                                     "playbackParts": order.filter { $0 == "play" }.count, "speechBeforeTranslationFinished": true]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("speech-results.json"))
        await pipeline.unload()
    }
}
