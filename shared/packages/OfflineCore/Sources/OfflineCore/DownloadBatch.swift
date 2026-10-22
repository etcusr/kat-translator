import Foundation

/// Persisted ownership of an unfinished user-started batch. A file that finishes
/// during this batch remains owned; preinstalled shared files never become owned.
public struct DownloadBatch: Codable, Sendable {
    public private(set) var ids: Set<String> = []
    public init() {}
    public mutating func include(_ requirements: [DownloadRequirement]) {
        ids.formUnion(requirements.filter { !$0.installed }.map(\.id))
    }
    /// Every owned file is installed, by whatever path (queue, row button, relaunch). The batch is then
    /// finished: keeping it would let a later "Cancel all" delete models the user has long been using.
    public func isComplete(installed: (String) -> Bool) -> Bool { !ids.isEmpty && ids.allSatisfy(installed) }
}
