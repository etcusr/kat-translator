import Foundation

public struct TranslationProgress: Sendable, Equatable {
    public let completedCharacters: Int
    public let totalCharacters: Int
    public let completedParts: Int
    public let totalParts: Int
    public let revision: Int
    public var fraction: Double { totalCharacters > 0 ? Double(completedCharacters) / Double(totalCharacters) : 0 }
}

/// Keeps progress in source characters, so retrying a smaller chunk does not rewind it.
public struct TranslationWork: Sendable {
    private var pieces: [String]
    private var index = 0
    private var completed = 0
    private var revision = 0
    private let total: Int
    public init(pieces: [String]) { self.pieces = pieces; total = pieces.reduce(0) { $0 + $1.count } }
    public var current: String? { index < pieces.count ? pieces[index] : nil }
    public var progress: TranslationProgress { .init(completedCharacters: completed, totalCharacters: total, completedParts: index, totalParts: pieces.count, revision: revision) }
    public mutating func completeCurrent() {
        guard let current else { return }
        completed += current.count; index += 1; revision += 1
    }
    public mutating func splitCurrent() throws {
        guard let current else { throw PipelineError.tooLong }
        let split = try TextSegments.bisect(current)
        pieces.replaceSubrange(index...index, with: [split.0, split.1]); revision += 1
    }
}
