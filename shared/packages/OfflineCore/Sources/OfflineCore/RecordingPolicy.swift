import Foundation
public enum RecordingMode: String, CaseIterable, Codable { case hold, toggle }
public enum RecordingInputEvent { case press, release, tap, cancel, stopped }
public enum RecordingCommand { case start, stop, cancel }
public struct RecordingInputState {
    public let mode: RecordingMode
    public private(set) var active = false
    public init(mode: RecordingMode) { self.mode = mode }
    public private(set) var latched = false
    public mutating func latchForPause() { if active { latched = true } }
    public mutating func handle(_ event: RecordingInputEvent) -> RecordingCommand? {
        switch event {
        case .press: guard mode == .hold, !active else { return nil }; active = true; return .start
        case .release: guard mode == .hold, active, !latched else { return nil }; active = false; return .stop
        case .tap: active.toggle(); if !active { latched = false }; return active ? .start : .stop
        case .cancel: let wasActive = active; active = false; latched = false; return wasActive ? .cancel : nil
        case .stopped: active = false; latched = false; return nil
        }
    }
}
public enum RecordingPolicy {
    public static let defaultMinutes = 10.0
    public static let maximumMinutes = 30.0
    public static func limitSeconds(minutes: Double) -> Int {
        let value = minutes.isFinite ? minutes : defaultMinutes
        return Int(min(maximumMinutes, max(1, value)).rounded()) * 60
    }
}
public struct BoundedRecordingBuffer {
    public private(set) var samples: [Float] = []
    private var signalled = false
    private let maxSamples: Int
    public init(maxSeconds: Int = RecordingPolicy.limitSeconds(minutes: RecordingPolicy.defaultMinutes)) {
        maxSamples = min(1800, max(1, maxSeconds)) * 16_000
    }
    public mutating func append(_ incoming: [Float]) -> Bool {
        samples.append(contentsOf: incoming.prefix(max(0, maxSamples - samples.count)))
        guard samples.count == maxSamples, !signalled else { return false }
        signalled = true; return true
    }
    public mutating func take() -> [Float] { let result = samples; samples = []; return result }
}

public struct RecordingClock {
    private let start: Double
    private var pausedAt: Double?
    private var pausedSeconds = 0.0
    public init(start: Double) { self.start = start }
    public func elapsed(at time: Double) -> Double { max(0, (pausedAt ?? time) - start - pausedSeconds) }
    public mutating func pause(at time: Double) { if pausedAt == nil { pausedAt = time } }
    public mutating func resume(at time: Double) {
        guard let pausedAt else { return }
        pausedSeconds += max(0, time - pausedAt); self.pausedAt = nil
    }
}
