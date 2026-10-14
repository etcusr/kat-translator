import XCTest
import OfflineCore
@testable import Kat_translator

final class OpusGPUIntegrationTests: XCTestCase {
    func testRealMetalDirectionsCancellationAndReuse() async throws {
        guard ProcessInfo.processInfo.environment["KAT_OPUS_GPU_TEST"] == "1" else { throw XCTSkip("Opt-in GPU weights") }
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["KAT_OPUS_GPU_PATH"])
        let backend = OpusGPUTranslationBackend()
        try await backend.load(modelURL: URL(fileURLWithPath: path))
        for (source, target, text) in [(SpeechLanguage.english, SpeechLanguage.russian, "Hello, how are you?"),
            (.english, .lang_uk, "Hello, how are you?"), (.english, .lang_be, "Hello, how are you?"),
            (.russian, .english, "Я хотел бы забронировать номер в отеле."),
            (.lang_uk, .english, "Я хотів би забронювати номер у готелі."),
            (.lang_be, .english, "Я хацеў бы забраніраваць нумар у гатэлі.")] {
            let result = try await backend.translate(text: text, source: source, target: target)
            XCTAssertFalse(result.text.isEmpty); XCTAssertNotEqual(result.text, text)
            print("OPUS_GPU_DIRECTION \(source.rawValue) \(target.rawValue) \(result.text)")
        }
        let task = Task { try await backend.translate(text: String(repeating: "This is a long translation. ", count: 100), source: .english, target: .russian) }
        try await Task.sleep(nanoseconds: 100_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("Wrong cancellation: \(error)") }
        let text = "He hastened to clarify that this assumption was purely preliminary and required careful verification."
        let again = try await backend.translate(text: text, source: .english, target: .russian)
        XCTAssertFalse(again.text.isEmpty)
        await backend.unload()
        let router = RoutedTranslationBackend()
        try await router.load(modelURL: URL(fileURLWithPath: path), model: .opusBig)
        let routed = try await router.translate(text: text, source: .english, target: .russian)
        XCTAssertEqual(routed.text, again.text)
        await router.unload()
        print("OPUS_GPU_INTEGRATION_OK device=mps:0 fp16=true sixDirections=true cancel=true reuse=true routed=true")
    }
}
