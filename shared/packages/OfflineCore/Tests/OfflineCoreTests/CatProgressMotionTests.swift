import XCTest
@testable import OfflineCore

final class CatProgressMotionTests: XCTestCase {
    func testFastDownloadCatchesUpWithJumpsAndLandsPromptly() {
        var cat = CatProgressMotion(progress: 0, now: 0)
        var jumped = false
        for frame in 0...90 {
            let t = Double(frame) / 60
            let progress = min(1, t * 0.9)
            cat.advance(progress: progress, active: true, now: t)
            jumped = jumped || cat.leap > 0
            XCTAssertLessThanOrEqual(cat.position, progress + 0.00001)
            if t > 0.5 { XCTAssertLessThan(progress - cat.position, 0.3) }
        }
        XCTAssertTrue(jumped)
        XCTAssertEqual(cat.position, 1, accuracy: 0.01)
    }
    func testIdleAnimationContinuesWithoutInventingDownloadProgress() {
        var cat = CatProgressMotion(progress: 0.4, now: 10)
        cat.advance(progress: 0.4, active: true, now: 24)
        XCTAssertEqual(cat.animationTime, 14)
        XCTAssertEqual(cat.position, 0.4)
        XCTAssertEqual(cat.phase, .sitting)
    }

    func testInactiveMotionReturnsToNeutralDecorativePose() {
        var cat = CatProgressMotion(progress: 0.4, now: 10)
        cat.advance(progress: 0.4, active: true, now: 24)
        cat.advance(progress: 0.4, active: false, now: 25)
        XCTAssertEqual(cat.animationTime, 0)
        XCTAssertEqual(cat.standing, 0)
        XCTAssertEqual(cat.position, 0.4)
    }
    func testRelativeDownloadSpeedChangesWalkToRun() {
        var slow = CatProgressMotion(progress: 0, now: 0)
        var fast = CatProgressMotion(progress: 0, now: 0)
        for frame in 1...60 {
            let time = Double(frame) / 30
            slow.advance(progress: time * 0.01, active: true, now: time)
            fast.advance(progress: time * 0.3, active: true, now: time)
        }
        XCTAssertEqual(slow.running, 0, accuracy: 0.01)
        XCTAssertEqual(fast.running, 1, accuracy: 0.01)
    }
    func testWalkNeverLeadsRealProgressAndEventuallySitsAtDestination() {
        var cat = CatProgressMotion(progress: 0, now: 0)
        var previous = 0.0
        var walked = false
        for frame in 0...240 {
            cat.advance(progress: 0.6, active: true, now: Double(frame) / 30)
            XCTAssertGreaterThanOrEqual(cat.position, previous)
            XCTAssertLessThanOrEqual(cat.position, 0.6)
            walked = walked || cat.phase == .walking
            previous = cat.position
        }
        XCTAssertTrue(walked)
        XCTAssertEqual(cat.position, 0.6, accuracy: 0.0001)
        XCTAssertEqual(cat.phase, .sitting)
        XCTAssertEqual(cat.standing, 0)
    }

    func testPauseAndRestartResetWithoutWalkingBackwards() {
        var cat = CatProgressMotion(progress: 0.2, now: 0)
        for frame in 0...45 { cat.advance(progress: 0.8, active: true, now: Double(frame) / 30) }
        cat.advance(progress: 0.8, active: false, now: 2)
        XCTAssertEqual(cat.phase, .sitting)
        XCTAssertEqual(cat.position, 0.8)
        cat.advance(progress: 0, active: true, now: 3)
        XCTAssertEqual(cat.position, 0)
        XCTAssertEqual(cat.phase, .sitting)
    }

    func testFrequentCallbacksDoNotRestartWalkAndCompletionIsReached() {
        var cat = CatProgressMotion(progress: 0, now: 0)
        for frame in 0...450 {
            let target = min(1, Double(frame) / 240)
            cat.advance(progress: target, active: true, now: Double(frame) / 30)
            XCTAssertLessThanOrEqual(cat.position, target + 0.00001)
        }
        XCTAssertEqual(cat.position, 1)
        XCTAssertEqual(cat.phase, .sitting)
        cat.advance(progress: .nan, active: false, now: 20)
        XCTAssertEqual(cat.position, 0)
    }
}
