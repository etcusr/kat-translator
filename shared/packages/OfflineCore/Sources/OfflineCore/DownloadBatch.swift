import Foundation

/// Persisted ownership of an unfinished user-started batch. A file that finishes
/// during this batch remains owned; preinstalled shared files never become owned.
public struct DownloadBatch: Codable, Sendable {
    public private(set) var ids: Set<String> = []
    public init() {}
    public mutating func include(_ requirements: [DownloadRequirement]) {
        ids.formUnion(requirements.filter { !$0.installed }.map(\.id))
    }
}
