import Foundation
public enum TextSegments {
    public static func split(_ text: String, fits: (String) -> Bool) throws -> [String] {
        guard !text.isEmpty else { return [] }
        if fits(text) { return [text] }
        let parts = try bisect(text)
        return try split(parts.0, fits: fits) + split(parts.1, fits: fits)
    }
    public static func bisect(_ text: String) throws -> (String, String) {
        let characters = Array(text)
        guard characters.count > 1 else { throw PipelineError.tooLong }
        let middle = characters.count / 2
        let candidates = (1..<characters.count).filter { abs($0 - middle) <= max(1, characters.count / 4) }
        let sentences = candidates.filter { ".!?\n。！？".contains(characters[$0 - 1]) }
        let words = candidates.filter { characters[$0 - 1].isWhitespace }
        let cut = (sentences.isEmpty ? words : sentences).min { abs($0 - middle) < abs($1 - middle) } ?? middle
        let index = text.index(text.startIndex, offsetBy: cut)
        return (String(text[..<index]), String(text[index...]))
    }
}
public struct SilenceMonitor {
    public static let defaultTimeout = 4.0
    public private(set) var heardSpeech = false
    private var quietSeconds = 0.0
    private var stopped = false
    private let timeout: Double
    public init(timeout: Double = SilenceMonitor.defaultTimeout) {
        self.timeout = timeout.isFinite ? min(30, max(1, timeout)) : Self.defaultTimeout
    }
    public mutating func observe(speech: Bool, seconds: Double) -> Bool {
        guard !stopped, seconds.isFinite, seconds >= 0 else { return false }
        if speech { heardSpeech = true; quietSeconds = 0 } else { quietSeconds += seconds }
        if quietSeconds >= timeout - 0.000001 { stopped = true; return true }
        return false
    }
}
