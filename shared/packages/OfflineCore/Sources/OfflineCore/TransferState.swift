import Foundation
public enum TransferPhase: String, Codable, Sendable { case idle, downloading, paused, checking, installed, restartRequired, failed }
public struct TransferState: Codable, Sendable {
    public var generation: Int = 0
    public var phase: TransferPhase = .idle
    public var receivedBytes: Int64 = 0
    public var expectedBytes: Int64
    public var error: String?
    public init(expectedBytes: Int64) { self.expectedBytes = expectedBytes }
    public mutating func start(resuming: Bool = false) { generation += 1; phase = .downloading; if !resuming { receivedBytes = 0 }; error = nil }
    public mutating func cancel() { generation += 1; phase = .idle; receivedBytes = 0; error = nil }
    public mutating func receive(_ bytes: Int64, generation: Int) {
        guard generation == self.generation, phase == .downloading else { return }
        receivedBytes = min(expectedBytes, max(0, bytes))
    }
    public mutating func finished(generation: Int) {
        guard generation == self.generation, phase == .downloading else { return }
        phase = .checking
    }
    public mutating func verified(generation: Int) {
        guard generation == self.generation, phase == .checking else { return }
        phase = .installed; receivedBytes = expectedBytes; error = nil
    }
    public mutating func pause(hasResumeData: Bool, generation: Int) {
        guard generation == self.generation, phase == .downloading else { return }
        phase = hasResumeData ? .paused : .restartRequired
    }
    public mutating func fail(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        phase = .failed; error = message
    }
}
