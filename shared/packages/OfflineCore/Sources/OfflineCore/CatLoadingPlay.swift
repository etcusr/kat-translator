import Foundation

/// Occasional decorative gestures, independent of download/model progress.
public struct CatLoadingPlay: Equatable, Sendable {
    public enum Trick: Int, CaseIterable, Sendable { case hop, doubleHop, somersault, mischief, wallKick, puke }
    public private(set) var trick: Trick?
    public private(set) var leap = 0.0
    public private(set) var crouch = 0.0
    public private(set) var rotation = 0.0
    /// Turn and distance away from the wall, applied by the presentation in either direction.
    public private(set) var turn = 0.0
    public private(set) var retreat = 0.0
    public static let wallRetreat = 0.24
    /// Leave about half a cat-length in front of the muzzle before springing back.
    public static func wallTakeoff(stepLength: Double) -> Double {
        1 - min(0.25, max(0.10, stepLength.isFinite ? stepLength * 0.55 : 0.15))
    }
    public static func wallLanding(from takeoff: Double) -> Double {
        min(1, max(0, 1 - takeoff + wallRetreat))
    }
    public enum Mark: Sendable { case pile, puddle }
    public private(set) var markKind = Mark.pile
    public private(set) var markCover = 0.0
    /// Forward displacement, committed by the view at landing before resuming the walk.
    public private(set) var travel = 0.0
    public private(set) var digging = 0.0
    public private(set) var retching = 0.0
    public private(set) var spill = 0.0
    public private(set) var heave = 0.0
    private var step = 0.18
    private var didLeaveMark = false
    public mutating func settleTravel() { travel = 0 }
    public private(set) var markPosition: Double?
    public private(set) var markFacingRight = true
    public private(set) var markOpacity = 0.0
    public var isPosing: Bool { trick == .mischief || trick == .wallKick || trick == .puke }
    private var randomState: UInt64
    private var nextAt: Double
    private var began = 0.0
    private var markAt: Double?

    public init(now: Double, seed: UInt64 = .random(in: .min ... .max)) {
        randomState = seed
        nextAt = now
        nextAt = now + delay(3...7)
    }
    private mutating func random() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / Double(UInt64(1) << 53)
    }
    private mutating func delay(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + random() * (range.upperBound - range.lowerBound)
    }
    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
    /// A wall event must not interrupt another trick or run on a random timer.
    @discardableResult public mutating func beginWallKick(now: Double) -> Bool {
        guard now.isFinite, trick == nil else { return false }
        trick = .wallKick; began = now
        return true
    }
    public mutating func advance(now: Double, position: Double, facingRight: Bool, stepLength: Double = 0.18) {
        guard now.isFinite else { return }
        if let markAt {
            let age = now - markAt
            markOpacity = min(1, max(0, (5 - age) / 1.3))
            if age >= 5 { self.markAt = nil; markPosition = nil; markOpacity = 0 }
        }
        if trick == nil && now >= nextAt {
            let choice = random()
            trick = choice < 0.44 ? .hop : choice < 0.65 ? .doubleHop : choice < 0.82 ? .somersault : choice < 0.91 ? .mischief : .puke
            let room = facingRight ? 1 - position : position
            step = stepLength.isFinite ? min(1, max(0, stepLength)) : 0.18
            // A full body-length jump needs a clear landing within the track.
            if trick == .puke && (step <= 0 || room < step) { trick = .hop }
            if trick == .mischief { step = min(step * 0.35, max(0, room)) }
            didLeaveMark = false
            began = now
        }
        guard let trick else { return }
        let elapsed = max(0, now - began)
        let duration: Double
        switch trick {
        case .hop: duration = 0.9
        case .doubleHop: duration = 1.7
        case .somersault: duration = 1.45
        case .mischief: duration = 5.2
        case .puke: duration = 4.5
        case .wallKick: duration = 0.92
        }
        let phase = min(1, elapsed / duration)
        switch trick {
        case .hop: leap = sin(.pi * phase)
        case .doubleHop: leap = abs(sin(.pi * 2 * phase)) * (phase < 0.5 ? 1 : 0.75)
        case .somersault:
            // Gather the paws, complete exactly one rotation in the air, land upright.
            let air = min(1, max(0, (elapsed - 0.16) / 1.10))
            leap = sin(.pi * air)
            rotation = 360 * smooth(air)
            crouch = elapsed < 0.16 ? sin(.pi * elapsed / 0.16) * 0.6
                : elapsed > 1.26 ? sin(.pi * min(1, (elapsed - 1.26) / 0.19)) * 0.35 : 0
        case .wallKick:
            let air = min(1, max(0, (elapsed - 0.14) / 0.60))
            // Brief coil, brisk ballistic push, then absorb the landing through the legs.
            crouch = elapsed < 0.14 ? smooth(elapsed / 0.14)
                : elapsed < 0.22 ? 1 - smooth((elapsed - 0.14) / 0.08)
                : elapsed > 0.74 ? sin(.pi * min(1, (elapsed - 0.74) / 0.18)) * 0.5 : 0
            leap = 4 * air * (1 - air)
            turn = smooth((air - 0.14) / 0.48)
            retreat = Self.wallRetreat * (1 - pow(1 - air, 2))
            rotation = -sin(.pi * air) * 22
        case .mischief:
            crouch = smooth(elapsed / 0.45) * (1 - smooth((elapsed - 1.5) / 0.5))
            if elapsed >= 1.25 && !didLeaveMark {
                leaveMark(.pile, now: now, position: position, facingRight: facingRight)
            }
            travel = step * smooth((elapsed - 1.8) / 0.6)
            digging = elapsed >= 2.4 && elapsed < 4.8 ? (elapsed - 2.4) / 2.4 : 0
            markCover = smooth((elapsed - 2.5) / 2.3)
            if elapsed >= 4.8 { markPosition = nil; markAt = nil; markOpacity = 0 }
        case .puke:
            retching = smooth(elapsed / 0.30) * (1 - smooth((elapsed - 2.55) / 0.35))
            // Three distinct abdominal contractions, with a relaxed beat between them.
            heave = 0
            for (start, length) in [(0.35, 0.32), (0.88, 0.34), (1.43, 0.36)] {
                if elapsed >= start && elapsed < start + length {
                    heave = pow(sin(.pi * (elapsed - start) / length), 2)
                }
            }
            crouch = retching * 0.15 + heave * 0.45
            spill = elapsed >= 2.0 && elapsed < 2.65 ? sin(.pi * (elapsed - 2.0) / 0.65) : 0
            if elapsed >= 2.15 && !didLeaveMark {
                leaveMark(.puddle, now: now, position: position, facingRight: facingRight)
            }
            let air = min(1, max(0, (elapsed - 3.1) / 1.0))
            leap = sin(.pi * air)
            travel = step * smooth(air)

        }
        if elapsed >= duration {
            self.trick = nil; leap = 0; crouch = 0; rotation = 0; turn = 0; retreat = 0
            retching = 0; spill = 0; digging = 0; heave = 0
            nextAt = now + delay(4.5...11)
        }
    }
    private mutating func leaveMark(_ kind: Mark, now: Double, position: Double, facingRight: Bool) {
        didLeaveMark = true; markAt = now; markOpacity = 1; markCover = 0
        markKind = kind
        markPosition = position.isFinite ? min(1, max(0, position)) : 0.5
        markFacingRight = facingRight
    }
}
