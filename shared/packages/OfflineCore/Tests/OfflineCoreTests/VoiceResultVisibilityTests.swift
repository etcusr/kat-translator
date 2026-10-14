import XCTest
@testable import OfflineCore

final class VoiceResultVisibilityTests: XCTestCase {
    func testFirstTranslationAppearsBeforeFinishingWorkflowReturns() {
        XCTAssertTrue(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: true,
            capturing: false, finishing: true, processing: true, preview: false, alreadyShown: false))
        XCTAssertFalse(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: false,
            capturing: false, finishing: true, processing: true, preview: false, alreadyShown: false))
    }
    func testPreviousResultAndRecordingPreviewStayHiddenDuringCaptureAndStop() {
        XCTAssertFalse(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: true,
            capturing: true, finishing: false, processing: false, preview: false, alreadyShown: true))
        XCTAssertFalse(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: true,
            capturing: false, finishing: true, processing: false, preview: false, alreadyShown: false))
        XCTAssertFalse(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: true,
            capturing: false, finishing: true, processing: true, preview: true, alreadyShown: false))
    }
    func testRevealedResultPersistsThroughAudioGapsAndHistoryRefresh() {
        for processing in [true, false] {
            XCTAssertTrue(VoiceResultVisibility.shouldShow(hasOriginal: true, hasTranslation: true,
                capturing: false, finishing: true, processing: processing, preview: false, alreadyShown: true))
        }
        XCTAssertFalse(VoiceResultVisibility.shouldShow(hasOriginal: false, hasTranslation: false,
            capturing: false, finishing: false, processing: false, preview: false, alreadyShown: true))
    }
}
