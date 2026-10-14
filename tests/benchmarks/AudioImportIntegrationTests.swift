import XCTest
import OfflineCore
@testable import Kat_translator

/// Opt-in, short real inference test. No test records are added to the user's history.
final class AudioImportIntegrationTests: XCTestCase {
    @MainActor func testAutomaticLanguageWithRealRecognitionAndTranslation() async throws {
        guard ProcessInfo.processInfo.environment["KAT_AUDIO_IMPORT_TESTS"] == "1" else { throw XCTSkip("Requires installed models") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let session = ConversationPipeline(asr: RoutedASRBackend(), translator: LlamaTranslationBackend(), speech: SherpaSpeechBackend(), player: SpeechPlayer(), archive: archive)
        let model = AppModel(session: session)
        await model.packages.restore(); await model.load()
        XCTAssertTrue(session.isReady)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audio-import", withExtension: "m4a"))
        let audio = try AudioFileImport.read(fixture)
        await session.run(audio: audio, source: nil, target: .french, speakResult: false, inputMode: "audio-file", thermal: "nominal")
        XCTAssertNil(session.error); XCTAssertEqual(session.resolvedSource, .english); XCTAssertEqual(session.resolvedTarget, .french)
        XCTAssertTrue(session.sourceText.lowercased().contains("tea"))
        XCTAssertTrue(session.translatedText.lowercased().contains("thé"))
        print("AUTO_SPEECH", session.sourceText, "=>", session.translatedText)
        let texts: [(SpeechLanguage, String)] = [
            (.lang_uk, "Доброго ранку! Підкажіть, будь ласка, де знаходиться найближча залізнична станція? Я хочу придбати квиток до Києва."),
            (.lang_be, "Добрай раніцы! Падкажыце, калі ласка, дзе знаходзіцца найбліжэйшы чыгуначны вакзал? Я хачу набыць квіток да Мінска.")
        ]
        for (language, text) in texts {
            await session.run(audio: nil, text: text, source: nil, target: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
            XCTAssertNil(session.error); XCTAssertEqual(session.resolvedSource, language); XCTAssertEqual(session.resolvedTarget, .russian)
            XCTAssertFalse(session.translatedText.isEmpty)
            if language == .lang_be { XCTAssertTrue(session.translatedText.lowercased().contains("билет")) }
            print("AUTO_TEXT", language.rawValue, "=>", session.translatedText)
        }
        let entries = try await archive.list()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.source), [.lang_be, .lang_uk, .english])
        XCTAssertEqual(entries.map(\.target), [.russian, .russian, .french])
        // Index echoed this Ukrainian sentence in the first real check. Compare against
        // manual source selection so a model-quality limitation is not mistaken for routing.
        let ukrainian = texts[0].1
        let automaticOutput = try XCTUnwrap(entries.first(where: { $0.source == .lang_uk })?.text?.translation)
        await session.run(audio: nil, text: ukrainian, source: .lang_uk, target: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        XCTAssertNil(session.error)
        XCTAssertEqual(session.translatedText, automaticOutput)
        print("UK_MANUAL_COMPARISON", session.translatedText == ukrainian ? "Index echoed source in both manual and auto modes" : "Manual and auto translations match")
        await model.unload()
    }
    @MainActor func testFileRecognitionTranslationAndHistory() async throws {
        guard ProcessInfo.processInfo.environment["KAT_AUDIO_IMPORT_TESTS"] == "1" else { throw XCTSkip("Requires installed models") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = TranslationHistory(root: root)
        let session = ConversationPipeline(asr: RoutedASRBackend(), translator: LlamaTranslationBackend(), speech: SherpaSpeechBackend(), player: SpeechPlayer(), archive: archive)
        let model = AppModel(session: session)
        await model.packages.restore()
        XCTAssertTrue(model.packages.ready)
        XCTAssertNil(model.voiceLanguageIssue)
        XCTAssertFalse(session.isReady)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audio-import", withExtension: "m4a"))
        let originalData = try Data(contentsOf: fixture)
        await model.importAudioFile(fixture)
        XCTAssertFalse(session.isReady, "Import is available only after explicit preparation")
        XCTAssertTrue(session.samples.isEmpty)
        await model.load()
        XCTAssertTrue(session.isReady)
        await model.importAudioFile(fixture)
        XCTAssertNil(model.message)
        XCTAssertNil(session.voiceFields.error)
        XCTAssertTrue(session.isReady)
        let source = session.voiceFields.sourceText
        let target = session.voiceFields.translatedText
        print("AUDIO_IMPORT_RESULT", source, "=>", target)
        XCTAssertTrue(source.lowercased().contains("tea"))
        XCTAssertTrue(source.lowercased().contains("thirty") || source.contains("30"), "The second sentence/end must survive")
        XCTAssertTrue(target.lowercased().contains("ча"))
        XCTAssertEqual(session.samples.last?.inputMode, "audio-file")
        XCTAssertEqual(session.samples.count, 1)
        XCTAssertFalse(model.recorder.isRecording)
        XCTAssertFalse(model.importingAudio)
        let history = try await archive.list()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.text?.original, source)
        XCTAssertEqual(history.first?.text?.translation, target)
        XCTAssertEqual(try Data(contentsOf: fixture), originalData)

        // A separate Text result survives another Voice import.
        await session.run(audio: nil, text: "Good morning.", source: .english, target: .russian, speakResult: false, inputMode: "text", thermal: "nominal")
        let textResult = session.textFields.translatedText
        XCTAssertFalse(textResult.isEmpty)
        await model.importAudioFile(fixture)
        XCTAssertEqual(session.textFields.translatedText, textResult)
        XCTAssertEqual(session.textFields.sourceText, "Good morning.")
        let completed = session.samples.count
        let previousVoice = session.voiceFields.translatedText
        let invalid = root.appendingPathComponent("broken.mp3")
        try Data("broken audio".utf8).write(to: invalid)
        await model.importAudioFile(invalid)
        XCTAssertNotNil(model.message)
        XCTAssertEqual(session.samples.count, completed, "Invalid files must not start recognition")
        XCTAssertEqual(session.voiceFields.translatedText, previousVoice, "A failed import must not erase the previous result")
        XCTAssertFalse(model.importingAudio)
        await model.unload()
    }
}
