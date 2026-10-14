import XCTest
@testable import OfflineCore
final class RecordingPolicyTests: XCTestCase {
    func testPauseExcludesWallTimeAndRepeatedTransitions() {
        var clock = RecordingClock(start: 100)
        XCTAssertEqual(clock.elapsed(at: 103), 3)
        clock.pause(at: 103)
        clock.pause(at: 109)
        XCTAssertEqual(clock.elapsed(at: 130), 3)
        clock.resume(at: 130)
        clock.resume(at: 131)
        XCTAssertEqual(clock.elapsed(at: 132), 5)
        clock.pause(at: 135)
        XCTAssertEqual(clock.elapsed(at: 200), 8)
    }
    func testHoldPauseLatchesUntilExplicitStopAndResetsForNextRecording() {
        var state = RecordingInputState(mode: .hold)
        XCTAssertEqual(state.handle(.press), .start)
        state.latchForPause()
        XCTAssertNil(state.handle(.release), "Lifting the holding finger must not end a paused recording")
        XCTAssertEqual(state.handle(.tap), .stop)
        XCTAssertEqual(state.handle(.press), .start)
        XCTAssertEqual(state.handle(.release), .stop)
    }
    func testHoldStartsOnceAndReleaseStopsPendingStart() {
        var state = RecordingInputState(mode: .hold)
        XCTAssertEqual(state.handle(.press), .start)
        XCTAssertNil(state.handle(.press))
        XCTAssertEqual(state.handle(.release), .stop)
        XCTAssertNil(state.handle(.release))
        XCTAssertEqual(state.handle(.press), .start)
        XCTAssertEqual(state.handle(.cancel), .cancel)
    }
    func testToggleAndAccessibilityUseStartStopPairs() {
        var state = RecordingInputState(mode: .toggle)
        XCTAssertEqual(state.handle(.tap), .start)
        XCTAssertEqual(state.handle(.tap), .stop)
        XCTAssertNil(state.handle(.release))
        var hold = RecordingInputState(mode: .hold)
        XCTAssertEqual(hold.handle(.tap), .start)
        XCTAssertEqual(hold.handle(.tap), .stop)
    }
    func testConfigurableLimitAndTenMinuteDefault() {
        XCTAssertEqual(RecordingPolicy.limitSeconds(minutes: 10), 600)
        XCTAssertEqual(RecordingPolicy.limitSeconds(minutes: 30), 1800)
        XCTAssertEqual(RecordingPolicy.limitSeconds(minutes: -1), 60)
        XCTAssertEqual(RecordingPolicy.limitSeconds(minutes: .nan), 600)
        var shorter = BoundedRecordingBuffer(maxSeconds: 60)
        XCTAssertFalse(shorter.append(Array(repeating: 0, count: 959_999)))
        XCTAssertTrue(shorter.append([0.25, 0.75]))
        XCTAssertEqual(shorter.samples.last, 0.25)
        XCTAssertEqual(shorter.samples.count, 960_000)
        XCTAssertFalse(shorter.append([1]))
        var defaultBuffer = BoundedRecordingBuffer()
        XCTAssertFalse(defaultBuffer.append(Array(repeating: 0, count: 4_800_000)), "Must not cut off at the former five-minute cap")
        XCTAssertTrue(defaultBuffer.append(Array(repeating: 0, count: 4_800_001)))
        XCTAssertEqual(defaultBuffer.samples.count, 9_600_000)
    }
    func testFullFiveMinutesRetainsTailAndSignalsLimitOnlyOnce() {
        var buffer = BoundedRecordingBuffer(maxSeconds: 300)
        XCTAssertFalse(buffer.append(Array(repeating: 0, count: 480_000)))
        XCTAssertFalse(buffer.append([0.75]))
        XCTAssertEqual(buffer.samples.dropFirst(480_000).first, 0.75)
        XCTAssertFalse(buffer.append(Array(repeating: 0, count: 4_319_998)))
        XCTAssertTrue(buffer.append([0.5, 0.9]))
        XCTAssertEqual(buffer.samples.count, 4_800_000)
        XCTAssertEqual(buffer.samples.last, 0.5)
        XCTAssertFalse(buffer.append([1]))
    }
}
