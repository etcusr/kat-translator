import XCTest
import OfflineCore
@testable import Kat_translator

private final class TranslationRouteSpy: TranslationBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private func append(_ value: String) { lock.lock(); defer { lock.unlock() }; calls.append(value) }
    var recorded: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    func load(modelURL: URL) async throws { append("load") }
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        append("translate"); return .init(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1)
    }
    func cancel() { append("cancel") }
    func unload() async { append("unload") }
}

final class OpusRoutingTests: XCTestCase {
    func testSwitchingRoutesTranslationAndUnloadsPreviousEngine() async throws {
        let llama = TranslationRouteSpy(), opus = TranslationRouteSpy()
        let router = RoutedTranslationBackend(llama: llama, opus: opus)
        try await router.load(modelURL: URL(fileURLWithPath: "/test/opus"), model: .opusBig)
        _ = try await router.translate(text: "Test", source: .english, target: .russian)
        XCTAssertEqual(opus.recorded.filter { $0 == "translate" }.count, 1)
        XCTAssertFalse(llama.recorded.contains("translate"))
        try await router.load(modelURL: URL(fileURLWithPath: "/test/index"), model: .index9B)
        _ = try await router.translate(text: "Test", source: .english, target: .russian)
        XCTAssertEqual(llama.recorded.filter { $0 == "translate" }.count, 1)
        XCTAssertEqual(opus.recorded.filter { $0 == "unload" }.count, 2)
        await router.unload()
        XCTAssertEqual(llama.recorded.last, "unload"); XCTAssertEqual(opus.recorded.last, "unload")
    }
}
