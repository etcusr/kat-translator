/// Hides the floating recording control when reading further down a result.
/// Passive layout changes and automatic scroll-to-result must not count as gestures.
public struct VoiceReadingScrollState: Equatable, Sendable {
    public private(set) var isHidden = false
    private var lastOffset: Double?
    private var travel: Double = 0

    public init() {}

    public mutating func update(offset: Double, userScrolling: Bool) {
        defer { lastOffset = offset }
        guard userScrolling, let lastOffset else { travel = 0; return }
        if offset <= 2 { isHidden = false; travel = 0; return }
        let delta = offset - lastOffset
        guard abs(delta) > 0.5 else { return }
        if delta * travel < 0 { travel = 0 }
        travel += delta
        if travel >= 18 { isHidden = true; travel = 0 }
        else if travel <= -28 { isHidden = false; travel = 0 }
    }
}
