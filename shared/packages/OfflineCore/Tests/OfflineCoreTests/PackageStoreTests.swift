import XCTest
@testable import OfflineCore
final class PackageStoreTests: XCTestCase {
    func testUpdateWithRelocatedContainerKeepsInstalledPackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRoot = root.appendingPathComponent("old-container")
        let installed = try await PackageStore(root: oldRoot).install(
            archive: Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, package: package)
        let newRoot = root.appendingPathComponent("updated-container")
        try FileManager.default.moveItem(at: oldRoot, to: newRoot)
        let restored = try await PackageStore(root: newRoot).readyDirectory(for: package)
        let directory = try XCTUnwrap(restored)
        XCTAssertEqual(directory.lastPathComponent, installed.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("a")), Data("abc".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("b")), Data("def".utf8))
    }
    func testUnchangedPackageSkipsHashesButChangedFileDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        let directory = try await store.install(archive: Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, package: package)
        let restarted = PackageStore(root: root)
        let ready = try await restarted.readyDirectory(for: package)
        let bytes = await restarted.validationBytesRead
        XCTAssertEqual(ready, directory)
        XCTAssertEqual(bytes, 0)
        try Data("xyz".utf8).write(to: directory.appendingPathComponent("a"))
        let changed = try await restarted.readyDirectory(for: package)
        let changedBytes = await restarted.validationBytesRead
        XCTAssertNil(changed)
        XCTAssertGreaterThan(changedBytes, 0)
    }

    let package = ModelPackage(id: "voice", archiveRoot: "voice", files: [
        PackageFile(path: "a", byteCount: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        PackageFile(path: "b", byteCount: 3, sha256: "cb8379ac2098aa165029e3938a51da0bcecfc008fd6795f401178647f96c5b34")])
    func testCompleteArchiveExtractsBothFilesWithExactBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try PackageArchive.extract(Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, to: root, package: package)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("a")), Data("abc".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("b")), Data("def".utf8))
    }
    func testUnsafeAndDuplicateEntriesCannotEscapeOrInstall() throws {
        for name in ["traversal", "absolute", "symlink", "duplicate"] {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: parent) }
            let root = parent.appendingPathComponent("staging")
            XCTAssertThrowsError(try PackageArchive.extract(Bundle.module.url(forResource: name + ".tar", withExtension: "bz2")!, to: root, package: package))
            XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape").path))
        }
    }
    func testUnexpectedSizeAndMissingFilesCannotBeReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrong = ModelPackage(id: "voice", archiveRoot: "voice", files: [PackageFile(path: "a", byteCount: 2, sha256: "bad")])
        XCTAssertThrowsError(try PackageArchive.extract(Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, to: root, package: wrong))
    }
    func testRestartRevalidatesInstalledPackageAndDetectsCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackageStore(root: root)
        let absent = try await store.readyDirectory(for: package); XCTAssertNil(absent)
        let directory = try await store.install(archive: Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, package: package)
        let restored = try await PackageStore(root: root).readyDirectory(for: package)
        XCTAssertEqual(restored, directory)
        try Data("bad".utf8).write(to: directory.appendingPathComponent("b"))
        let corrupt = try await PackageStore(root: root).readyDirectory(for: package); XCTAssertNil(corrupt)
    }
    func testSeparateDownloadsAreVerifiedBeforeBecomingReady() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let a = parent.appendingPathComponent("download1.bin"), b = parent.appendingPathComponent("download2.bin")
        try Data("abc".utf8).write(to: a); try Data("def".utf8).write(to: b)
        let store = PackageStore(root: parent.appendingPathComponent("packages"))
        do { _ = try await store.install(files: ["a": a], package: package); XCTFail("Partial package accepted") } catch {}
        let absent = try await store.readyDirectory(for: package); XCTAssertNil(absent)
        let directory = try await store.install(files: ["a": a, "b": b], package: package)
        let ready = try await store.readyDirectory(for: package); XCTAssertEqual(directory, ready)
        try Data("bad".utf8).write(to: b)
        do { _ = try await store.install(files: ["a": a, "b": b], package: package); XCTFail("Corruption accepted") } catch {}
        let preserved = try await store.readyDirectory(for: package); XCTAssertEqual(preserved, directory)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("b")), Data("def".utf8))
        let unsafe = ModelPackage(id: "escape", archiveRoot: "escape", files: [PackageFile(path: "../outside", byteCount: 3, sha256: package.files[0].sha256)])
        do { _ = try await store.install(files: ["../outside": a], package: unsafe); XCTFail("Traversal accepted") } catch {}
    }
    func testPiperPreparationVerifiesDerivedBytesBeforePublishing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("raw.onnx")
        try Data("ab".utf8).write(to: input)
        let prepared = PiperPreparation(metadataSuffix: Data("c".utf8), tokens: "def")
        let manifest = ModelPackage(id: "piper", archiveRoot: "piper", files: [
            PackageFile(path: "model.onnx", byteCount: 3, sha256: package.files[0].sha256),
            PackageFile(path: "tokens.txt", byteCount: 3, sha256: package.files[1].sha256)])
        let store = PackageStore(root: root.appendingPathComponent("packages"))
        let result = try await store.installPiper(model: input, preparation: prepared, package: manifest)
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("model.onnx")), Data("abc".utf8))
        XCTAssertEqual(try Data(contentsOf: input), Data("ab".utf8))
        do {
            _ = try await store.installPiper(model: input, preparation: .init(metadataSuffix: Data("x".utf8), tokens: "def"), package: manifest)
            XCTFail("Incorrect derived bytes accepted")
        } catch {}
        let preserved = try await store.readyDirectory(for: manifest)
        XCTAssertEqual(preserved, result)
    }

}
