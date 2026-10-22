import Foundation

/// Opt-in small source chunks. Context is not carried across boundaries.
public enum TranslationChunks {
    /// Splits `text` into pieces of at most `limit` tokens, preferring sentence, then whitespace boundaries.
    /// Each chunk is located by an exponential then binary search over its own prefix, so tokenizer work
    /// grows with the chunk rather than with the remaining text. `cancelled` is checked between probes.
    public static func plan(_ text: String, limit: Int = 128, count: (String) -> Int,
                            cancelled: () -> Bool = { false }) throws -> [String] {
        guard limit > 0 else { throw PipelineError.tooLong }
        var rest = text[...], parts: [String] = []
        let sentence = try NSRegularExpression(pattern: #"\n\s*\n|\n|[.!?。！？][\"”’\)]?\s+"#)
        let whitespace = try NSRegularExpression(pattern: #"\s+"#)
        func check() throws { if cancelled() { throw CancellationError() } }
        func fits(_ length: Int) -> Bool { count(String(rest.prefix(length))) <= limit }
        while !rest.isEmpty {
            try check()
            let total = rest.count
            // Largest prefix length known to fit (`low`) and smallest known not to fit (`high + 1`).
            var low = 0, high = total, probe = min(total, max(1, limit * 4))
            while true {
                try check()
                if fits(probe) {
                    low = probe
                    if probe == total { break }
                    probe = min(total, probe * 2)
                } else { high = probe - 1; break }
            }
            if low == total { parts.append(String(rest)); break }
            while low < high {
                try check()
                let middle = (low + high + 1) / 2
                if fits(middle) { low = middle } else { high = middle - 1 }
            }
            guard low > 0 else { throw PipelineError.tooLong }
            var bounded = String(rest.prefix(low))
            let range = NSRange(bounded.startIndex..., in: bounded)
            if let match = sentence.matches(in: bounded, range: range).last ?? whitespace.matches(in: bounded, range: range).last,
               let boundary = Range(NSRange(location: 0, length: match.range.upperBound), in: bounded) {
                bounded = String(bounded[boundary])
            }
            // Tokenizers are not strictly monotonic at prefix boundaries.
            while count(bounded) > limit && !bounded.isEmpty { try check(); bounded.removeLast() }
            guard !bounded.isEmpty else { throw PipelineError.tooLong }
            parts.append(bounded); rest = rest.dropFirst(bounded.count)
        }
        return parts
    }
}
