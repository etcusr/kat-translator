import XCTest
@testable import OfflineCore

final class VoicePackageCatalogTests: XCTestCase {
    private func part(_ id: String, path: String) -> VoicePackagePart {
        VoicePackagePart(id: id, path: path, remoteURL: URL(string: "https://example.com/" + id)!, byteCount: 10, sha256: String(repeating: "a", count: 64))
    }
    func testComponentOwnershipAndUnrelatedDownloads() throws {
        let voice = VoicePackageDefinition(id: "test-model", language: "tl", title: "MMS", license: "CC BY-NC", sourceURL: URL(string: "https://example.com")!, kind: .files,
            parts: [part("test-model", path: "model.onnx"), part("test-tokens", path: "tokens.txt")])
        let catalog = try VoicePackageCatalog([voice])
        XCTAssertEqual(catalog.package(containing: "test-tokens")?.id, "test-model")
        XCTAssertEqual(catalog.voices(language: "tl"), [voice])
        XCTAssertNil(catalog.package(containing: "translation"))
        XCTAssertEqual(voice.models.map(\.id), ["test-model", "test-tokens"])
    }
    func testRejectsSharedComponentsAndUnsafePaths() throws {
        let first = VoicePackageDefinition(id: "first", language: "tl", title: "MMS", license: "NC", sourceURL: URL(string: "https://example.com")!, kind: .files, parts: [part("first", path: "model.onnx"), part("shared", path: "tokens.txt")])
        let second = VoicePackageDefinition(id: "second", language: "ta", title: "MMS", license: "NC", sourceURL: URL(string: "https://example.com")!, kind: .files, parts: [part("second", path: "model.onnx"), part("shared", path: "tokens.txt")])
        XCTAssertThrowsError(try VoicePackageCatalog([first, second]))
        let unsafe = VoicePackageDefinition(id: "bad", language: "ta", title: "MMS", license: "NC", sourceURL: URL(string: "https://example.com")!, kind: .files, parts: [part("bad", path: "../model.onnx")])
        XCTAssertThrowsError(try VoicePackageCatalog([unsafe]))
    }
    func testMultilingualPackSharesOneDownloadWithoutChangingExistingDefaults() throws {
        let shared = VoicePackageDefinition(id: "shared-base", language: "en", title: "OmniVoice", license: "NC", sourceURL: URL(string: "https://example.com")!, kind: .files,
            parts: [part("shared-base", path: "base.gguf"), part("shared-codec", path: "codec.gguf")], languageAliases: ["en": "en", "ru": "ru", "lo": "lao"])
        let catalog = try VoicePackageCatalog([shared])
        XCTAssertEqual(catalog.voices(language: "ru"), [shared])
        XCTAssertEqual(catalog.voices(language: "lo").first?.runtimeLanguage("lo"), "lao")
        XCTAssertEqual(catalog.package(containing: "shared-codec")?.id, "shared-base")
        XCTAssertTrue(catalog.voices(language: "ban").isEmpty)
    }

}
