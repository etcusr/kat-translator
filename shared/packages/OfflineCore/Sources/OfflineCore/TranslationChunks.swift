import Foundation

/// Opt-in small source chunks. Context is not carried across boundaries.
public enum TranslationChunks {
    public static func plan(_ text: String, limit: Int = 128, count: (String) -> Int) throws -> [String] {
        guard limit > 0 else { throw PipelineError.tooLong }
        var rest = text[...], parts: [String] = []
        let sentence = try NSRegularExpression(pattern: #"\n\s*\n|\n|[.!?。！？][\"”’\)]?\s+"#)
        let whitespace = try NSRegularExpression(pattern: #"\s+"#)
        while !rest.isEmpty {
            let value = String(rest)
            if count(value) <= limit { parts.append(value); break }
            let chars = Array(rest)
            var low = 0, high = chars.count
            while low < high {
                let middle = (low + high + 1) / 2
                if count(String(chars.prefix(middle))) <= limit { low = middle } else { high = middle - 1 }
            }
            guard low > 0 else { throw PipelineError.tooLong }
            var bounded = String(chars.prefix(low))
            let range = NSRange(bounded.startIndex..., in: bounded)
            if let match = sentence.matches(in: bounded, range: range).last ?? whitespace.matches(in: bounded, range: range).last,
               let boundary = Range(NSRange(location: 0, length: match.range.upperBound), in: bounded) {
                bounded = String(bounded[boundary])
            }
            // Tokenizers are not strictly monotonic at prefix boundaries.
            while count(bounded) > limit && !bounded.isEmpty { bounded.removeLast() }
            guard !bounded.isEmpty else { throw PipelineError.tooLong }
            parts.append(bounded); rest = rest.dropFirst(bounded.count)
        }
        return parts
    }
}
