import XCTest
@testable import OfflineCore
final class ExpandedVoiceIntegrationTests: XCTestCase {
    private var root: URL { (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() } }
    func testBundledCatalogHasManifestPreviewAndMatchingLanguageCapability() throws {
        let url = root.appendingPathComponent("assets/catalogs/additional-voices.json")
        let voices = try JSONDecoder().decode([VoicePackageDefinition].self, from: Data(contentsOf: url))
        _ = try VoicePackageCatalog(voices)
        XCTAssertGreaterThan(voices.count, 15)
        let packages = try JSONDecoder().decode([ModelPackage].self, from: Data(contentsOf: root.appendingPathComponent("assets/catalogs/voice-manifests.json")))
        for voice in voices {
            XCTAssertEqual(SpeechLanguage(rawValue: voice.language)?.hasVoice, true, voice.id)
            XCTAssertTrue(packages.contains { $0.id == voice.id }, voice.id)
            for code in voice.languageAliases?.keys.map({ $0 }) ?? [voice.language] {
                XCTAssertEqual(SpeechLanguage(rawValue: code)?.hasVoice, true, code)
                let suffix = voice.languageAliases == nil ? "" : "-" + code
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/bundled/VoicePreviews/" + voice.id + suffix + ".m4a").path), voice.id + suffix)
            }
        }
        // Existing assignments retain their stable model IDs and are not replaced by expansion.
        XCTAssertTrue(Set(voices.filter { $0.languageAliases == nil }.map(\.language)).isDisjoint(with: ["ru", "en", "th", "zh", "ban"]))
    }
    func testRealMMSPreviewTextSurvivesNativeAlphabetValidation() throws {
        guard ProcessInfo.processInfo.environment["OT_TTS_FIXTURES"] == "1" else { throw XCTSkip("Downloaded voice fixtures are opt-in") }
        let voices = try JSONDecoder().decode([VoicePackageDefinition].self, from: Data(contentsOf: root.appendingPathComponent("assets/catalogs/additional-voices.json")))
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/benchmarks/tts-round2/results.json"))) as! [[String: Any]]
        for voice in voices where voice.kind == .files && voice.id.hasPrefix("mms-tts-") {
            let code = voice.id.replacingOccurrences(of: "mms-tts-", with: "").replacingOccurrences(of: "-onnx", with: "")
            let tokens = try String(contentsOf: root.appendingPathComponent("model-store/downloads/tts-round2/mms-" + code + "/tokens.txt"), encoding: .utf8)
            let text = report.first { $0["id"] as? String == voice.id }!["text"] as! String
            XCTAssertNoThrow(try MMSSpeechText.prepare(text, tokens: tokens, language: voice.language), voice.id)
        }
    }
}
