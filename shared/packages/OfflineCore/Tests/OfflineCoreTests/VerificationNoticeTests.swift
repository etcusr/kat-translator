import XCTest
@testable import OfflineCore

private final class VerificationEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func add(_ value: Bool) { lock.lock(); values.append(value); lock.unlock() }
    var events: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
}
final class VerificationNoticeTests: XCTestCase {
    func testModelNoticeOnlyForExistingModelWithoutCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ModelDescriptor(id: "fixture", title: "Fixture", remoteURL: URL(string: "https://example.com/model")!, byteCount: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let events = VerificationEvents()
        let store = ModelStore(root: root, onUncachedVerification: events.add)
        _ = try await store.installedURL(for: model)
        XCTAssertEqual(events.events, []) // Nothing downloaded: no slow first check.
        try Data("abc".utf8).write(to: root.appendingPathComponent("fixture.bin"))
        try JSONEncoder().encode(model).write(to: root.appendingPathComponent("fixture.json"))
        _ = try await store.installedURL(for: model)
        XCTAssertEqual(events.events, [true, false])
        _ = try await store.installedURL(for: model)
        XCTAssertEqual(events.events, [true, false]) // Cached startup must stay silent.
        try Data("xyz".utf8).write(to: root.appendingPathComponent("fixture.bin"))
        _ = try await store.installedURL(for: model)
        XCTAssertEqual(events.events, [true, false, true, false]) // Stale cache also requires the slow check.
    }
    func testPackageNoticeIsBalancedAndAbsentOnCachedStartup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = ModelPackage(id: "voice", archiveRoot: "voice", files: [
            PackageFile(path: "a", byteCount: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            PackageFile(path: "b", byteCount: 3, sha256: "cb8379ac2098aa165029e3938a51da0bcecfc008fd6795f401178647f96c5b34")])
        let events = VerificationEvents()
        let store = PackageStore(root: root, onUncachedVerification: events.add)
        _ = try await store.readyDirectory(for: package)
        XCTAssertEqual(events.events, [])
        _ = try await store.install(archive: Bundle.module.url(forResource: "valid.tar", withExtension: "bz2")!, package: package)
        _ = try await store.readyDirectory(for: package)
        XCTAssertEqual(events.events, [])
        try FileManager.default.removeItem(at: root.appendingPathComponent("voice.verified.json"))
        _ = try await store.readyDirectory(for: package)
        XCTAssertEqual(events.events, [true, false])
        _ = try await store.readyDirectory(for: package)
        XCTAssertEqual(events.events, [true, false])
    }
}
