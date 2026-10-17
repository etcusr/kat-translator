import XCTest
@testable import OfflineCore
final class ReviewRegressionTests: XCTestCase {
    func testPendingCancelledStartupMustDrainBeforeAnotherPress() throws {
        var gate = RecordingStartGate()
        let first = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.isCurrent(first))
        gate.cancel() // Release while system permission or VAD is still pending.
        XCTAssertFalse(gate.isCurrent(first), "Cancelled startup must not activate the microphone")
        XCTAssertNil(gate.begin(), "A second press cannot claim a no-op recorder.start as success")
        XCTAssertFalse(gate.settle(first, succeeded: true), "Late permission must not resurrect cancelled capture")
        let second = try XCTUnwrap(gate.begin())
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
        XCTAssertTrue(gate.settle(second, succeeded: true))
        XCTAssertTrue(gate.isCurrent(second), "Successful capture remains current until stopped")
        XCTAssertNil(gate.begin(), "Active capture must exclude another startup")
        gate.cancel()
        XCTAssertFalse(gate.isCurrent(second))
        XCTAssertNotNil(gate.begin())
    }
    func testFailedStartupInvalidatesTokenAndAllowsRetry() throws {
        var gate = RecordingStartGate()
        let failed = try XCTUnwrap(gate.begin())
        XCTAssertFalse(gate.isCurrent(failed + 1))
        XCTAssertFalse(gate.settle(failed, succeeded: false))
        XCTAssertFalse(gate.isCurrent(failed))
        let retry = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.isCurrent(retry))
        XCTAssertFalse(gate.settle(failed, succeeded: false), "Late cleanup cannot invalidate a newer request")
        XCTAssertTrue(gate.isCurrent(retry))
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.settle(retry, succeeded: true))
    }
    func testEmbeddedNULFailsExplicitlyInsteadOfTranslatingPrefix() {
        XCTAssertThrowsError(try TranslationPrompt.validate("First sentence.\0Do not cancel the order."))
        XCTAssertNoThrow(try TranslationPrompt.validate("First sentence. Do not cancel the order."))
    }
}
