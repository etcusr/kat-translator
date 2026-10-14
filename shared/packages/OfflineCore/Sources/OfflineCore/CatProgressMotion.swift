import Foundation

/// Decorative progress follower. Byte accounting remains owned by the downloader.
public struct CatProgressMotion: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case sitting, rising, walking, jumping, settling }
    public private(set) var phase: Phase = .sitting
    public private(set) var position: Double
    public private(set) var standing = 0.0
    public private(set) var stride = 0.0
    /// Local decorative clock. Resetting for pause/Reduce Motion gives a neutral pose.
    public private(set) var animationTime = 0.0
    /// 0 = a measured stroll, 1 = a run. Relative progress speed includes file size.
    public private(set) var running = 0.0
    private var lastTarget: Double
    private var sampledAt: Double
    private var rate = 0.0
    private var began: Double
    private var origin = 0.0
    private var destination = 0.0
    public private(set) var leap = 0.0
    private var jumpDuration = 0.35
    private var previousTime: Double
    private var createdAt: Double

    public init(progress: Double, now: Double) {
        position = Self.clamp(progress); lastTarget = position; began = now; sampledAt = now; createdAt = now; previousTime = now
    }
    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    private func smooth(_ value: Double) -> Double {
        let t = Self.clamp(value)
        return t * t * (3 - 2 * t)
    }
    public mutating func advance(progress: Double, active: Bool, now: Double) {
        let target = Self.clamp(progress)
        // A restarted transfer or a changed package must not leave the cat ahead.
        if !active || target < lastTarget {
            self = Self(progress: target, now: now)
            return
        }
        let dt = min(0.1, max(0, now - previousTime))
        previousTime = now
        animationTime = max(0, now - createdAt)
        if target > lastTarget {
            let sample = min(1, (target - lastTarget) / max(0.033, now - sampledAt))
            rate = rate == 0 ? sample : rate * 0.65 + sample * 0.35
            sampledAt = now
        }
        lastTarget = target
        let elapsed = max(0, now - began)
        let gap = max(0, target - position)
        switch phase {
        case .sitting:
            if gap > 0.00001 && elapsed >= (rate > 0.12 ? 0.06 : 0.35) {
                running = Self.clamp((rate - 0.025) / 0.16)
                phase = .rising; began = now
            }
        case .rising:
            let duration = rate > 0.12 ? 0.12 : 0.24
            standing = smooth(elapsed / duration)
            if elapsed >= duration { phase = .walking; standing = 1; began = now }
        case .walking:
            running = Self.clamp((rate - 0.025) / 0.16)
            // Follow the current target continuously, not a stale waypoint.
            if elapsed > 0.10 && gap > 0.08 && (rate > 0.45 || gap > 0.18) {
                origin = position; destination = target
                jumpDuration = min(0.4, max(0.22, gap / max(0.6, rate * 2)))
                phase = .jumping; began = now
            } else {
                position = min(target, position + max(0.025, rate * 1.35 + gap * 3) * dt)
                stride = sin(animationTime * .pi * 2 * (1.2 + 2.8 * running))
                if target - position < 0.00001 && now - sampledAt > 0.18 {
                    stride = 0; phase = .settling; began = now
                }
            }
        case .jumping:
            let fraction = Self.clamp(elapsed / jumpDuration)
            position = min(target, origin + (destination - origin) * fraction)
            leap = sin(fraction * .pi)
            stride = -leap * 0.7
            if fraction >= 1 {
                position = min(target, destination); leap = 0; stride = 0
                phase = .walking; began = now
            }
        case .settling:
            // Resume promptly if data arrives while the cat is sitting down.
            if gap > 0.01 {
                phase = .rising; began = now - standing * 0.12
            } else {
                standing = 1 - smooth(elapsed / 0.25)
                if elapsed >= 0.25 { standing = 0; phase = .sitting; began = now }
            }
        }
    }
}
