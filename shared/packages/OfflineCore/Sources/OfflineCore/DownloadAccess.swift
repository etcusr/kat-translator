import Foundation

public enum DownloadNetworkState: Sendable, Equatable {
    case unknown, offline, wifi, wired, cellular, expensive
    public var requiresConfirmation: Bool { self != .wifi && self != .wired }
    public func canDownload(allowCellular: Bool) -> Bool {
        switch self {
        case .unknown, .offline: false
        case .wifi, .wired: true
        case .cellular, .expensive: allowCellular
        }
    }
}

public struct DownloadAccessItem: Sendable {
    public let id: String
    public let bytes: Int64
    public let phase: TransferPhase
    public let installed: Bool
    public init(id: String, bytes: Int64, phase: TransferPhase, installed: Bool) {
        self.id = id; self.bytes = bytes; self.phase = phase; self.installed = installed
    }
    /// An upper bound: a resumed request may need to restart when its network
    /// permission changes or the server no longer accepts its resume data.
    public static func maximumDownloadBytes(_ items: [Self]) -> Int64 {
        var seen = Set<String>()
        return items.filter { !$0.installed && ![.installed, .checking, .downloading].contains($0.phase) && seen.insert($0.id).inserted }
            .reduce(0) { $0 + max(0, $1.bytes) }
    }
    public static func canResume(previousCellular: Bool?, allowCellular: Bool) -> Bool {
        previousCellular == allowCellular
    }
}
