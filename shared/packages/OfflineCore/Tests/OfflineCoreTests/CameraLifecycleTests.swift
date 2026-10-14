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
}
