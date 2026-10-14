import Foundation

public enum OpusTextSegments {
    /// Sentence boundaries use source text only. Preserve separators, including paragraph breaks,
    /// so splitting for Marian's bounded input cannot silently drop or reorder source characters.
    public static func split(_ text: String, fits: (String) -> Bool) throws -> [String] {
        guard !text.isEmpty else { return [] }
        let boundary = try NSRegularExpression(pattern: #"[.!?]["”»]?(\s+)(?=[A-ZА-ЯЁІЇЄҐЎ"“«])|(\n\s*\n)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var starts = [text.startIndex]
        for match in boundary.matches(in: text, range: range) {
            let separator = match.range(at: match.range(at: 1).location != NSNotFound ? 1 : 2)
            if let part = Range(separator, in: text), part.lowerBound > starts.last! { starts.append(part.lowerBound) }
        }
        starts.append(text.endIndex)
        return try zip(starts, starts.dropFirst()).flatMap { lower, upper in
            try TextSegments.split(String(text[lower..<upper]), fits: fits)
        }
    }
}
