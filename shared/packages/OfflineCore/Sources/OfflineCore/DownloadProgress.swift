import Foundation

/// Network completion and package readiness are different: 100% can still need verification.
public struct DownloadProgress: Sendable {
    public struct Item: Sendable {
        public var id: String
        public var expected: Int64
        public var received: Int64
        public var phase: TransferPhase
        public var ready: Bool
        public var packageFailed: Bool
        public init(id: String, expected: Int64, received: Int64, phase: TransferPhase, ready: Bool, packageFailed: Bool = false) {
            self.id = id; self.expected = expected; self.received = received
            self.phase = phase; self.ready = ready; self.packageFailed = packageFailed
        }
    }
    public enum Status: Sendable { case downloading, verifying, paused, failed, cancelled, ready }
    public let total: Int64
    public let received: Int64
    public let status: Status
    public var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }
    public var finished: Bool { [.ready, .cancelled, .failed].contains(status) }
    public init(_ input: [Item]) {
        var seen = Set<String>()
        let items = input.filter { seen.insert($0.id).inserted }
        total = items.reduce(0) { $0 + max(0, $1.expected) }
        received = items.reduce(0) { $0 + ($1.ready || $1.phase == .installed ? max(0, $1.expected) : max(0, min($1.received, $1.expected))) }
        if items.isEmpty { status = .cancelled }
        else if items.allSatisfy(\.ready) { status = .ready }
        else if items.contains(where: { $0.phase == .downloading }) { status = .downloading }
        else if items.contains(where: { $0.phase == .checking }) { status = .verifying }
        else if items.contains(where: { $0.packageFailed || [.failed, .restartRequired].contains($0.phase) }) { status = .failed }
        else if items.contains(where: { $0.phase == .installed && !$0.ready }) { status = .verifying }
        else if items.contains(where: { $0.phase == .paused }) { status = .paused }
        else { status = .cancelled }
    }
}
