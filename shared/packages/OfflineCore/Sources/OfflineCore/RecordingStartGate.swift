/// Keeps an abandoned permission/native startup in flight until its async call returns.
public struct RecordingStartGate {
    private var generation = 0
    private var pending: Int?
    private var active = false
    public init() {}
    public mutating func begin() -> Int? {
        guard !active, pending == nil else { return nil }
        generation += 1; pending = generation; active = true; return generation
    }
    /// Check validity after an await without draining a pending native startup.
    public func isCurrent(_ token: Int) -> Bool { generation == token && active }
    public mutating func cancel() { generation += 1; active = false }
    @discardableResult public mutating func settle(_ token: Int, succeeded: Bool) -> Bool {
        if pending == token { pending = nil }
        guard generation == token, active else { return false }
        if !succeeded { active = false }
        return succeeded
    }
}
