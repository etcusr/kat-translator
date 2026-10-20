import XCTest
@testable import OfflineCore

final class ModelStoreTests: XCTestCase {
    func testUpdateWithRelocatedContainerAndChangedDisplayMetadataKeepsModel() async throws {
        let parent = try directory(), oldRoot = parent.appendingPathComponent("old-container")
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        let old = fixture()
        _ = try await ModelStore(root: oldRoot).verifyAndInstall(stagingURL: staging, model: old)
        let newRoot = parent.appendingPathComponent("updated-container")
        try FileManager.default.moveItem(at: oldRoot, to: newRoot)
        let updated = ModelDescriptor(id: old.id, title: "Updated name",
            remoteURL: URL(string: "https://example.com/new-mirror")!,
            byteCount: old.byteCount, sha256: old.sha256)
        let restored = try await ModelStore(root: newRoot).installedURL(for: updated)
        let file = try XCTUnwrap(restored)
        XCTAssertEqual(try Data(contentsOf: file), Data("abc".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newRoot.appendingPathComponent("fixture.json").path))
    }
    func testUnchangedVerifiedModelRestartsWithoutReadingWeights() async throws {
        let root = try directory(), staging = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        _ = try await ModelStore(root: root).verifyAndInstall(stagingURL: staging, model: fixture())
        let restarted = ModelStore(root: root)
        let ready = try await restarted.installedURL(for: fixture())
        let bytes = await restarted.validationBytesRead
        XCTAssertNotNil(ready)
        XCTAssertEqual(bytes, 0)
    }

    func testLegacyReceiptIsFullyVerifiedOnceThenCached() async throws {
        let root = try directory()
        try Data("abc".utf8).write(to: root.appendingPathComponent("fixture.bin"))
        try JSONEncoder().encode(fixture()).write(to: root.appendingPathComponent("fixture.json"))
        let first = ModelStore(root: root)
        _ = try await first.installedURL(for: fixture())
        let firstBytes = await first.validationBytesRead
        XCTAssertEqual(firstBytes, 3)
        let second = ModelStore(root: root)
        _ = try await second.installedURL(for: fixture())
        let secondBytes = await second.validationBytesRead
        XCTAssertEqual(secondBytes, 0)
    }

    func testSameSizeChangeWithRestoredModificationDateInvalidatesCache() async throws {
        let root = try directory(), staging = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        let installed = try await ModelStore(root: root).verifyAndInstall(stagingURL: staging, model: fixture())
        let date = try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate]!
        try Data("xyz".utf8).write(to: installed)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: installed.path)
        let restarted = ModelStore(root: root)
        let ready = try await restarted.installedURL(for: fixture())
        let bytes = await restarted.validationBytesRead
        XCTAssertNil(ready)
        XCTAssertEqual(bytes, 3)
    }
    let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    func fixture(hash: String? = nil, id: String = "fixture") -> ModelDescriptor {
        ModelDescriptor(id: id, title: "Fixture", remoteURL: URL(string: "https://example.com/model")!,
                        byteCount: 3, sha256: hash ?? abcHash)
    }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testWrongDigestIsNeverInstalled() async throws {
        let root = try directory(); let file = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: file)
        let model = fixture(hash: String(repeating: "0", count: 64))
        let store = ModelStore(root: root)
        do { _ = try await store.verifyAndInstall(stagingURL: file, model: model); XCTFail("Corrupt file installed") }
        catch ModelStoreError.invalidDigest {}
        let installed = try await store.installedURL(for: model)
        XCTAssertNil(installed)
    }
    func testDigestAcrossMultipleReadBlocksAndPartialFinalBlock() async throws {
        let root = try directory(), file = root.appendingPathComponent("staging")
        let size = 2 * 1_048_576 + 3
        try Data(repeating: 120, count: size).write(to: file)
        let model = ModelDescriptor(id: "blocks", title: "Blocks", remoteURL: URL(string: "https://example.com/model")!,
            byteCount: Int64(size), sha256: "62f6606ca219021620d1d69cbb0c3c5ba014019d0e9c8bbdb05b44683c68f29c")
        let store = ModelStore(root: root)
        let installed = try await store.verifyAndInstall(stagingURL: file, model: model)
        let restored = try await store.installedURL(for: model)
        XCTAssertEqual(restored, installed)
    }
    func testTruncatedFileIsNeverInstalled() async throws {
        let root = try directory(); let file = root.appendingPathComponent("partial")
        try Data("ab".utf8).write(to: file)
        do { _ = try await ModelStore(root: root).verifyAndInstall(stagingURL: file, model: fixture()); XCTFail("Truncation accepted") }
        catch ModelStoreError.invalidSize {}
    }
    func testInstalledFileSurvivesStoreRestartAndCanBeDeleted() async throws {
        let root = try directory(); let file = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: file)
        let model = fixture(); let store = ModelStore(root: root)
        let installed = try await store.verifyAndInstall(stagingURL: file, model: model)
        XCTAssertNotEqual(installed, file)
        XCTAssertEqual(try Data(contentsOf: installed), Data("abc".utf8))
        let restarted = ModelStore(root: root)
        let restored = try await restarted.installedURL(for: model)
        XCTAssertEqual(restored, installed)
        try await restarted.remove(model)
        let removed = try await restarted.installedURL(for: model)
        XCTAssertNil(removed)
    }
    func testUnverifiedStagingIsNotReadyAndCanBeRecovered() async throws {
        let root = try directory(); let staging = root.appendingPathComponent("staging")
        try Data("abc".utf8).write(to: staging)
        let store = ModelStore(root: root)
        let before = try await store.installedURL(for: fixture())
        XCTAssertNil(before)
        _ = try await store.verifyAndInstall(stagingURL: staging, model: fixture())
        let after = try await store.installedURL(for: fixture())
        XCTAssertNotNil(after)
    }
    func testModifiedInstalledFileFailsRevalidation() async throws {
        let root = try directory(); let staging = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        let store = ModelStore(root: root)
        let installed = try await store.verifyAndInstall(stagingURL: staging, model: fixture())
        try Data("xyz".utf8).write(to: installed)
        let recovered = try await ModelStore(root: root).installedURL(for: fixture())
        XCTAssertNil(recovered)
    }
    func testRenamingOrMovingDownloadDoesNotInvalidateVerifiedWeights() async throws {
        let root = try directory(), staging = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        let store = ModelStore(root: root), old = fixture()
        let installed = try await store.verifyAndInstall(stagingURL: staging, model: old)
        let renamed = ModelDescriptor(id: old.id, title: "31 languages", remoteURL: URL(string: "https://example.com/new-mirror")!, byteCount: old.byteCount, sha256: old.sha256)
        let restored = try await store.installedURL(for: renamed)
        XCTAssertEqual(restored, installed)
        let different = ModelDescriptor(id: old.id, title: renamed.title, remoteURL: renamed.remoteURL, byteCount: old.byteCount, sha256: String(repeating: "f", count: 64))
        let stale = try await store.installedURL(for: different)
        XCTAssertNil(stale)
    }
    func testPathTraversalIsRejected() async throws {
        let root = try directory(); let staging = root.appendingPathComponent("partial")
        try Data("abc".utf8).write(to: staging)
        do { _ = try await ModelStore(root: root).verifyAndInstall(stagingURL: staging, model: fixture(id: "../outside")); XCTFail("Traversal accepted") }
        catch ModelStoreError.invalidIdentifier {}
    }
}
