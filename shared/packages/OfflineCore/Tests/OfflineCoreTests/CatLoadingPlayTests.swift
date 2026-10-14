import XCTest
@testable import OfflineCore

final class CatLoadingPlayTests: XCTestCase {
    func testOccasionalVariedGesturesAndBoundedAnimation() {
        var play = CatLoadingPlay(now: 0, seed: 42)
        var seen = Set<Int>(), starts: [Double] = []
        var previous: CatLoadingPlay.Trick?
        for tick in 0..<18_000 {
            let time = Double(tick) / 30
            play.advance(now: time, position: 0.45, facingRight: true)
            XCTAssertTrue((0...1).contains(play.leap))
            XCTAssertTrue((0...1).contains(play.crouch))
            XCTAssertTrue((0...1).contains(play.markOpacity))
            XCTAssertTrue(play.rotation.isFinite)
            if let trick = play.trick, previous == nil {
                starts.append(time); seen.insert(trick.rawValue)
            }
            previous = play.trick
            if time < 3 { XCTAssertNil(play.trick) }
        }
        XCTAssertEqual(seen, Set([CatLoadingPlay.Trick.hop, .doubleHop, .somersault, .mischief, .puke].map(\.rawValue)))
        XCTAssertLessThan(starts.count, 90, "Gestures should remain occasional, not continuous bouncing")
        XCTAssertGreaterThan(Set(zip(starts, starts.dropFirst()).map { Int(($1 - $0) * 10) }).count, 10)
    }
    func testSomersaultCompletesOneTurnAndLandsUpright() throws {
        var play = CatLoadingPlay(now: 0, seed: 42)
        var time = 0.0
        while play.trick != .somersault && time < 300 {
            time += 1.0 / 30
            play.advance(now: time, position: 0.5, facingRight: true)
        }
        XCTAssertEqual(play.trick, .somersault)
        let start = time
        play.advance(now: start + 0.71, position: 0.5, facingRight: true)
        XCTAssertEqual(play.rotation, 180, accuracy: 0.001)
        XCTAssertEqual(play.leap, 1, accuracy: 0.001)
        play.advance(now: start + 1.27, position: 0.5, facingRight: true)
        XCTAssertEqual(play.rotation, 360, accuracy: 0.001)
        XCTAssertEqual(play.leap, 0, accuracy: 0.001)
        play.advance(now: start + 1.46, position: 0.5, facingRight: true)
        XCTAssertNil(play.trick)
        XCTAssertEqual(play.rotation, 0)
    }
    func testWallKickTurnsInwardAndDoesNotInterruptAnotherTrick() {
        for facingRight in [true, false] {
            var play = CatLoadingPlay(now: 0, seed: 42)
            XCTAssertTrue(play.beginWallKick(now: 0))
            XCTAssertFalse(play.beginWallKick(now: 0.1))
            let takeoff = CatLoadingPlay.wallTakeoff(stepLength: 0.28)
            XCTAssertLessThan(takeoff, 0.9)
            let edge = facingRight ? takeoff : 1 - takeoff
            var previousRetreat = 0.0
            for tick in 0...91 {
                play.advance(now: Double(tick) / 100, position: edge, facingRight: facingRight)
                XCTAssertTrue(play.isPosing)
                XCTAssertGreaterThanOrEqual(play.retreat, previousRetreat)
                let renderedPosition = edge + (facingRight ? -play.retreat : play.retreat)
                XCTAssertTrue((0...1).contains(renderedPosition))
                previousRetreat = play.retreat
            }
            XCTAssertEqual(play.turn, 1)
            XCTAssertEqual(play.retreat, CatLoadingPlay.wallRetreat, accuracy: 0.001)
            play.advance(now: 0.93, position: edge, facingRight: facingRight)
            XCTAssertNil(play.trick)
            XCTAssertEqual(play.leap, 0)
            XCTAssertEqual(play.crouch, 0)
            // At either wall the caller's mirrored landing position is continuous.
            let before = edge + (facingRight ? -previousRetreat : previousRetreat)
            let landing = CatLoadingPlay.wallLanding(from: takeoff)
            let after = facingRight ? 1 - landing : landing
            XCTAssertEqual(before, after, accuracy: 0.001)
        }
        var play = CatLoadingPlay(now: 0, seed: 42)
        play.advance(now: 10, position: 0.5, facingRight: true)
        XCTAssertNotNil(play.trick)
        XCTAssertFalse(play.beginWallKick(now: 10))
    }
    private func scheduled(_ trick: CatLoadingPlay.Trick, facingRight: Bool = true, position: Double = 0.32) throws -> CatLoadingPlay {
        for seed in UInt64(0)..<4096 {
            var play = CatLoadingPlay(now: 0, seed: seed)
            play.advance(now: 7, position: position, facingRight: facingRight, stepLength: 0.2)
            if play.trick == trick { return play }
        }
        throw NSError(domain: "No scheduled trick", code: 1)
    }
    func testPileIsBuriedWithRearPawsBeforeWalkingAway() throws {
        var play = try scheduled(.mischief)
        play.advance(now: 8.3, position: 0.32, facingRight: true)
        XCTAssertEqual(play.markKind, .pile)
        XCTAssertEqual(play.markPosition, 0.32)
        XCTAssertEqual(play.markOpacity, 1)
        play.advance(now: 10.3, position: 0.8, facingRight: false)
        XCTAssertGreaterThan(play.digging, 0)
        XCTAssertGreaterThan(play.markCover, 0)
        XCTAssertEqual(play.markPosition, 0.32, "The pile stays on the ground")
        XCTAssertTrue(play.markFacingRight)
        XCTAssertGreaterThan(play.travel, 0)
        play.advance(now: 12.3, position: 0.8, facingRight: false)
        XCTAssertNil(play.trick)
        XCTAssertNil(play.markPosition)
        XCTAssertEqual(play.digging, 0)
        XCTAssertGreaterThan(play.travel, 0, "Caller commits the landing before clearing the offset")
        play.settleTravel()
        XCTAssertEqual(play.travel, 0)
    }
    func testPukePrecedesJumpAndLandsBeyondPuddleInBothDirections() throws {
        for right in [true, false] {
            var play = try scheduled(.puke, facingRight: right, position: 0.5)
            play.advance(now: 9.35, position: 0.5, facingRight: right)
            XCTAssertGreaterThan(play.retching, 0)
            XCTAssertGreaterThan(play.spill, 0)
            XCTAssertEqual(play.leap, 0)
            XCTAssertEqual(play.markKind, .puddle)
            XCTAssertEqual(play.markFacingRight, right)
            play.advance(now: 10.6, position: 0.5, facingRight: right)
            XCTAssertGreaterThan(play.leap, 0.9)
            XCTAssertGreaterThan(play.travel, 0)
            XCTAssertEqual(play.retching, 0)
            XCTAssertEqual(play.markPosition, 0.5)
            play.advance(now: 11.6, position: 0.5, facingRight: right)
            XCTAssertNil(play.trick)
            XCTAssertEqual(play.travel, 0.2, accuracy: 0.0001)
            XCTAssertEqual(play.leap, 0)
            play.settleTravel()
            play.advance(now: 14.5, position: 0.9, facingRight: right)
            XCTAssertNil(play.markPosition)
        }
    }
    func testThreeBodyHeavesBeforePukeWithNoEarlySpill() throws {
        var play = try scheduled(.puke)
        for peak in [0.51, 1.05, 1.61] {
            play.advance(now: 7 + peak, position: 0.32, facingRight: true)
            XCTAssertGreaterThan(play.heave, 0.9)
            XCTAssertEqual(play.spill, 0)
            XCTAssertNil(play.markPosition)
            play.advance(now: 7 + peak + 0.23, position: 0.32, facingRight: true)
            XCTAssertLessThan(play.heave, 0.05)
        }
    }
    func testWallSpringHasFastLiftAndSoftLanding() {
        var play = CatLoadingPlay(now: 0)
        XCTAssertTrue(play.beginWallKick(now: 0))
        play.advance(now: 0.12, position: 0.85, facingRight: true)
        XCTAssertGreaterThan(play.crouch, 0.5)
        play.advance(now: 0.32, position: 0.85, facingRight: true)
        XCTAssertGreaterThan(play.leap, 0.8)
        play.advance(now: 0.83, position: 0.85, facingRight: true)
        XCTAssertEqual(play.leap, 0, accuracy: 0.001)
        XCTAssertGreaterThan(play.crouch, 0.2)
        XCTAssertEqual(play.turn, 1)
    }
    func testPukeRequiresLandingRoomAtEitherEdge() {
        for right in [true, false] {
            for seed in UInt64(0)..<100 {
                var play = CatLoadingPlay(now: 0, seed: seed)
                play.advance(now: 7, position: right ? 0.95 : 0.05, facingRight: right, stepLength: 0.2)
                XCTAssertNotEqual(play.trick, .puke)
            }
        }
    }
}
