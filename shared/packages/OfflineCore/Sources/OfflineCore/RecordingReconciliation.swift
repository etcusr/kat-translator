import Foundation
import NaturalLanguage

public struct RecordingPreviewBlock: Sendable {
    public let source: String
    public let translation: String
    public init(source: String, translation: String) { self.source = source; self.translation = translation }
}

/// Recognition reconciliation, not a semantic correctness score. Reuse only unique,
/// ordered whole-sentence matches. A changed span includes its immediate neighbors.
public struct RecordingReconciliation: Sendable {
    public struct Part: Sendable {
        public let source: String
        public let translation: String?
    }
    public let parts: [Part]
    public let reusedBlocks: Int
    public var confirmedPrefix: String {
        parts.prefix { $0.translation != nil }.compactMap(\.translation).joined(separator: " ")
    }
    public init(finalText: String, blocks: [RecordingPreviewBlock]) {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = finalText
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: finalText.startIndex..<finalText.endIndex) { range, _ in
            let text = String(finalText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { sentences.append(text) }
            return true
        }
        let keys = sentences.map(Self.key)
        var owners = Array<Int?>(repeating: nil, count: sentences.count)
        var cursor = 0
        for (blockID, block) in blocks.enumerated() {
            let wanted = Self.key(block.source)
            guard !wanted.isEmpty, !block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var matches: [Range<Int>] = []
            for start in keys.indices {
                var candidate = ""
                for end in start..<keys.count {
                    candidate += (candidate.isEmpty ? "" : " ") + keys[end]
                    if candidate == wanted { matches.append(start..<(end + 1)) }
                    if candidate.count >= wanted.count { break }
                }
            }
            guard matches.count == 1, let match = matches.first, match.lowerBound >= cursor else { continue }
            for index in match { owners[index] = blockID }
            cursor = match.upperBound
        }
        // Invalidate entire blocks touched by adjacent context, without recursively
        // expanding through every block in the recording.
        let changed = owners.indices.filter { owners[$0] == nil }
        var invalid: Set<Int> = []
        for index in changed {
            for neighbor in max(0, index - 1)...min(owners.count - 1, index + 1) {
                if let owner = owners[neighbor] { invalid.insert(owner) }
            }
        }
        for index in owners.indices { if let owner = owners[index], invalid.contains(owner) { owners[index] = nil } }
        var output: [Part] = []
        var index = 0
        var reused = 0
        while index < sentences.count {
            let owner = owners[index]
            var end = index + 1
            while end < sentences.count && owners[end] == owner { end += 1 }
            output.append(Part(source: sentences[index..<end].joined(separator: " "), translation: owner.map { blocks[$0].translation }))
            if owner != nil { reused += 1 }
            index = end
        }
        parts = output; reusedBlocks = reused
    }
    private static func key(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
