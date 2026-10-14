import XCTest
@testable import OfflineCore

final class VoiceReadingScrollStateTests: XCTestCase {
    func testReadingDownHidesAndReadingUpRestoresControl() {
        var state = VoiceReadingScrollState()
        state.update(offset: 230, userScrolling: false) // auto-scroll to the translation
        XCTAssertFalse(state.isHidden)
        state.update(offset: 242, userScrolling: true)
        XCTAssertFalse(state.isHidden) // small incidental movement
        state.update(offset: 260, userScrolling: true)
        XCTAssertTrue(state.isHidden)
        state.update(offset: 255, userScrolling: true)
        XCTAssertTrue(state.isHidden) // no flicker on a tiny reverse movement
        state.update(offset: 230, userScrolling: true)
        XCTAssertFalse(state.isHidden)
    }

    func testLayoutChangesDoNotToggleAndTopRestoresControl() {
        var state = VoiceReadingScrollState()
        state.update(offset: 0, userScrolling: false)
        state.update(offset: 100, userScrolling: true)
        XCTAssertTrue(state.isHidden)
        state.update(offset: 45, userScrolling: false) // viewport or text changes
        XCTAssertTrue(state.isHidden)
        state.update(offset: 0, userScrolling: true)
        XCTAssertFalse(state.isHidden)
    }
}
