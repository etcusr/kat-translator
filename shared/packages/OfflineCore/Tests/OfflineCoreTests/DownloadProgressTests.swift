import XCTest
@testable import OfflineCore
final class DownloadProgressTests: XCTestCase {
    func testFullTransferWaitsForVerificationAndAssembly() {
        for phase in [TransferPhase.checking, .installed] {
            let value = DownloadProgress([.init(id: "p", expected: 100, received: 100, phase: phase, ready: false)])
            XCTAssertEqual(value.fraction, 1); XCTAssertEqual(value.status, .verifying); XCTAssertFalse(value.finished)
        }
        XCTAssertTrue(DownloadProgress([.init(id: "p", expected: 100, received: 100, phase: .installed, ready: true)]).finished)
    }
    func testFailedFileDoesNotEndOtherActiveTransfers() {
        let good = DownloadProgress.Item(id: "g", expected: 100, received: 20, phase: .downloading, ready: false)
        let bad = DownloadProgress.Item(id: "b", expected: 100, received: 0, phase: .failed, ready: false)
        XCTAssertFalse(DownloadProgress([good, bad]).finished)
        var done = good; done.phase = .installed; done.ready = true
        XCTAssertEqual(DownloadProgress([done, bad]).status, .failed)
    }
    func testSharedFilesCountOnceAndAssemblyFailureIsVisible() {
        let item = DownloadProgress.Item(id: "shared", expected: 100, received: 120, phase: .installed, ready: false, packageFailed: true)
        let value = DownloadProgress([item, item])
        XCTAssertEqual(value.total, 100); XCTAssertEqual(value.received, 100); XCTAssertEqual(value.status, .failed)
    }
    func testPausedProgressRetainsDownloadedBytes() {
        var state = TransferState(expectedBytes: 100); state.start(); state.receive(45, generation: state.generation)
        state.pause(hasResumeData: true, generation: state.generation)
        let old = state.generation
        state.start(resuming: true)
        XCTAssertEqual(state.receivedBytes, 45)
        state.receive(90, generation: old)
        XCTAssertEqual(state.receivedBytes, 45)
        state.start(); XCTAssertEqual(state.receivedBytes, 0)
    }
}
