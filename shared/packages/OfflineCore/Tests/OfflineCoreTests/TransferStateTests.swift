import XCTest
@testable import OfflineCore
final class TransferStateTests: XCTestCase {
    func testDownloadedFileIsNotReadyUntilVerified() {
        var state = TransferState(expectedBytes: 3); state.start()
        let generation = state.generation
        state.receive(3, generation: generation); state.finished(generation: generation)
        XCTAssertEqual(state.phase, .checking)
        state.verified(generation: generation)
        XCTAssertEqual(state.phase, .installed)
    }
    func testCancelledDownloadCannotCompleteOrOverwriteNewDownload() {
        var state = TransferState(expectedBytes: 3); state.start()
        let old = state.generation; state.cancel(); state.start()
        state.finished(generation: old); state.verified(generation: old); state.receive(99, generation: old)
        XCTAssertEqual(state.phase, .downloading)
        XCTAssertEqual(state.receivedBytes, 0)
        state.fail("old error", generation: old)
        XCTAssertNil(state.error)
    }
    func testMissingResumeDataRequiresExplicitRestart() {
        var state = TransferState(expectedBytes: 3); state.start()
        state.pause(hasResumeData: false, generation: state.generation)
        XCTAssertEqual(state.phase, .restartRequired)
    }
    func testResumeDataCanPauseAndProgressNeverExceedsExpected() {
        var state = TransferState(expectedBytes: 3); state.start()
        state.receive(99, generation: state.generation)
        XCTAssertEqual(state.receivedBytes, 3)
        state.pause(hasResumeData: true, generation: state.generation)
        XCTAssertEqual(state.phase, .paused)
    }
    func testFailureIsVisibleAndNewAttemptClearsIt() {
        var state = TransferState(expectedBytes: 3); state.start()
        state.fail("HTTP 404", generation: state.generation)
        XCTAssertEqual(state.phase, .failed); XCTAssertEqual(state.error, "HTTP 404")
        state.start(); XCTAssertNil(state.error)
    }
}
