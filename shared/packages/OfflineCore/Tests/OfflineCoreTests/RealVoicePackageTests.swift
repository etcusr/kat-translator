import XCTest
@testable import OfflineCore
final class RealVoicePackageTests: XCTestCase {
    func testPinnedVoiceArchivesWithProductionManifests() async throws {
        guard let project = ProcessInfo.processInfo.environment["OFFLINE_ASSET_TEST_ROOT"] else { throw XCTSkip("Optional verified upstream assets are not downloaded in ordinary unit tests") }
        let root = URL(fileURLWithPath: project)
        let packages = try JSONDecoder().decode([ModelPackage].self, from: Data(contentsOf: root.appendingPathComponent("assets/catalogs/voice-manifests.json")))
        let store = PackageStore(root: root.appendingPathComponent(".build/verified-voices"))
        for package in packages {
            let archive = root.appendingPathComponent("model-store/downloads/" + package.archiveRoot + ".tar.bz2")
            let directory: URL
            if let existing = try await store.readyDirectory(for: package) { directory = existing }
            else { directory = try await store.install(archive: archive, package: package) }
            let ready = try await store.readyDirectory(for: package)
            XCTAssertEqual(ready, directory)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(package.id.contains("supertonic") ? "tts.json" : "tokens.txt").path))
        }
    }
}
