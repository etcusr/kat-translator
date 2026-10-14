import XCTest
import OfflineCore
@testable import Kat_translator

/// Opt-in (KAT_COMPACT_INTEGRATION=1): real Index 2B GGUF and OPUS direction packages from the
/// shared model-store research cache, through the shipping RoutedTranslationBackend.
final class CompactModelsIntegrationTests: XCTestCase {
    private var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func testDeviceProbeIndex2BAndOpusDirections() async throws {
        guard ProcessInfo.processInfo.environment["KAT_COMPACT_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in compact model integration") }
        let probe = await DeviceProbe.run()
        print("COMPACT_PROBE", probe)
        XCTAssertGreaterThan(probe.cpuGbps, 0); XCTAssertGreaterThan(probe.gpuGbps, 0); XCTAssertGreaterThan(probe.estimate9B, 0)

        let router = RoutedTranslationBackend()
        let model2B = repo.appendingPathComponent("model-store/research/index-2b/Index-Translate-2B.Q4_K_M.gguf")
        try await router.load(modelURL: model2B, model: .index2B)
        let english = try await router.translate(text: "Поезд до Казани отправится завтра в 07:45.", source: .russian, target: .english)
        print("COMPACT_2B", english.processingSeconds, english.text)
        XCTAssertTrue(english.text.localizedCaseInsensitiveContains("train"), english.text)

        // Direction packages are laid out as the PackageStore installs them: <root>/<package id>/<direction>/.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("opus-directions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for direction in ["zle-de", "de-zle"] {
            let route = try XCTUnwrap(OpusDirectionRoutes.all.first { $0.direction == direction })
            let package = root.appendingPathComponent(route.packageID)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let manifest = ModelPackage(id: route.packageID, archiveRoot: route.packageID, files: route.parts.map { PackageFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256) })
            try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("receipt.json"))
            try FileManager.default.createSymbolicLink(at: package.appendingPathComponent(direction),
                withDestinationURL: repo.appendingPathComponent("model-store/research/opus-pairs/" + direction))
        }
        try await router.load(modelURL: root, model: .opusDirections)
        let german = try await router.translate(text: "Поезд до Казани отправится завтра в 07:45.", source: .russian, target: .german)
        print("COMPACT_RU_DE", german.processingSeconds, german.text)
        XCTAssertTrue(german.text.contains("Zug"), german.text)
        let russian = try await router.translate(text: "Der Zug nach Kasan fährt morgen um 07:45 ab.", source: .german, target: .russian)
        print("COMPACT_DE_RU", russian.processingSeconds, russian.text)
        XCTAssertTrue(russian.text.contains("Поезд") || russian.text.contains("поезд"), russian.text)
        await router.unload()
    }
}
