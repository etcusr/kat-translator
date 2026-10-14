import XCTest
import OfflineCore
@testable import Kat_translator

final class TranslationRollbackTests: XCTestCase {
    func testArticleMatchesPackagedBuild17() async throws {
        guard ProcessInfo.processInfo.environment["KAT_RUN_TRANSLATION_ROLLBACK_TEST"] == "1" else {
            throw XCTSkip("Opt-in real-model rollback verification")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("tests/fixtures/context-comparison-yandex-ru.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = try String(contentsOf: root.appendingPathComponent("docs/benchmarks/long-context/build17/translation-en.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let backend = LlamaTranslationBackend()
        try await backend.load(modelURL: root.appendingPathComponent("model-store/downloads/Index-Translate-9B.Q4_K_M.gguf"), model: .index9B)
        do {
            let result = try await backend.translate(text: source, source: .russian, target: .english)
            XCTAssertEqual(result.fragments, 1, "The article must be translated together, as in build17")
            XCTAssertEqual(result.text, expected, "The restored backend must reproduce the packaged build17 translation")
        } catch {
            await backend.unload()
            throw error
        }
        await backend.unload()
    }
}
