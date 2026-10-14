import XCTest
@testable import OfflineCore
final class ReviewRegressionTests: XCTestCase {
    func testPendingCancelledStartupMustDrainBeforeAnotherPress() throws {
        var gate = RecordingStartGate()
        let first = try XCTUnwrap(gate.begin())
        gate.cancel() // Release while system permission or VAD is still pending.
        XCTAssertNil(gate.begin(), "A second press cannot claim a no-op recorder.start as success")
        XCTAssertFalse(gate.settle(first, succeeded: true), "Late permission must not resurrect cancelled capture")
        let second = try XCTUnwrap(gate.begin())
        XCTAssertTrue(gate.settle(second, succeeded: true))
        gate.cancel()
        XCTAssertNotNil(gate.begin())
    }
    func testEmbeddedNULFailsExplicitlyInsteadOfTranslatingPrefix() {
        XCTAssertThrowsError(try TranslationPrompt.validate("First sentence.\0Do not cancel the order."))
        XCTAssertNoThrow(try TranslationPrompt.validate("First sentence. Do not cancel the order."))
    }
}
