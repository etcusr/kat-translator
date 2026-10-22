import XCTest
@testable import OfflineCore

@MainActor final class CameraLifecycleTests: XCTestCase {
    func testLaterCloseInvalidatesOpenWaitingForPreviousClose() async {
        let gate = CameraActivationGate()
        var release: CheckedContinuation<Void,Never>?
        let closing = Task { await withCheckedContinuation { release = $0 } }
        while release == nil { await Task.yield() }
        let opening = Task { await gate.waitForClose(closing) }
        for _ in 0..<10 { await Task.yield() }
        gate.invalidate(); release?.resume()
        let allowed = await opening.value
        XCTAssertFalse(allowed)
        let next = await gate.waitForClose(nil)
        XCTAssertTrue(next)
    }
    func testCancelledOpenCannotRestartCameraAfterDrain() async {
        let gate = CameraActivationGate()
        var release: CheckedContinuation<Void,Never>?
        let closing = Task { await withCheckedContinuation { release = $0 } }
        while release == nil { await Task.yield() }
        let opening = Task { await gate.waitForClose(closing) }
        for _ in 0..<10 { await Task.yield() }
        opening.cancel(); release?.resume()
        let allowed = await opening.value
        XCTAssertFalse(allowed)
    }
    func testImportCancellationResetsBusyAndOldResultCannotAffectNewImport() async {
        let importer = ImageImportSession()
        var first: CheckedContinuation<Data?,Error>?
        var second: CheckedContinuation<Data?,Error>?
        var results: [Data] = []
        importer.start(load: { try await withCheckedThrowingContinuation { first = $0 } }, consume: { results.append($0) })
        while first == nil { await Task.yield() }
        XCTAssertTrue(importer.busy)
        importer.cancel(); XCTAssertFalse(importer.busy)
        importer.start(load: { try await withCheckedThrowingContinuation { second = $0 } }, consume: { results.append($0) })
        while second == nil { await Task.yield() }
        first?.resume(returning: Data([1]))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(importer.busy); XCTAssertTrue(results.isEmpty)
        second?.resume(returning: Data([2]))
        while importer.busy { await Task.yield() }
        XCTAssertEqual(results, [Data([2])])
    }
    func testCancelledPhotoImportDeletesFileReturnedAfterCancellation() async throws {
        let importer = ImageImportSession()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var release: CheckedContinuation<URL?, Never>?
        var consumed = false, cleaned = false
        importer.start(load: { await withCheckedContinuation { release = $0 } }, cleanup: {
            try? FileManager.default.removeItem(at: $0); cleaned = true
        }, consume: { _ in consumed = true })
        while release == nil { await Task.yield() }
        importer.cancel()
        try Data([1, 2, 3]).write(to: file)
        release?.resume(returning: file)
        while !cleaned { await Task.yield() }
        XCTAssertFalse(consumed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(importer.busy)
    }
    func testReplacingPhotoImportCleansOldPayloadWithoutRemovingCurrentFile() async throws {
        let importer = ImageImportSession()
        let firstFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secondFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: firstFile); try? FileManager.default.removeItem(at: secondFile) }
        try Data([1]).write(to: firstFile); try Data([2]).write(to: secondFile)
        var first: CheckedContinuation<URL?, Never>?, second: CheckedContinuation<URL?, Never>?
        var cleaned: [URL] = [], consumed: [URL] = []
        let cleanup: (URL) -> Void = { try? FileManager.default.removeItem(at: $0); cleaned.append($0) }
        importer.start(load: { await withCheckedContinuation { first = $0 } }, cleanup: cleanup, consume: { consumed.append($0) })
        while first == nil { await Task.yield() }
        importer.start(load: { await withCheckedContinuation { second = $0 } }, cleanup: cleanup, consume: {
            XCTAssertTrue(FileManager.default.fileExists(atPath: $0.path))
            consumed.append($0)
        })
        while second == nil { await Task.yield() }
        first?.resume(returning: firstFile)
        while cleaned.isEmpty { await Task.yield() }
        XCTAssertTrue(importer.busy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondFile.path))
        XCTAssertTrue(consumed.isEmpty)
        second?.resume(returning: secondFile)
        while importer.busy { await Task.yield() }
        XCTAssertEqual(consumed, [secondFile])
        XCTAssertEqual(cleaned, [firstFile, secondFile])
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondFile.path))
    }
}
