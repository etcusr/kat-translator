import Foundation

/// Conservative planning for the fixed 2048-token runtime with a 1536-token input cap.
/// The response length is an estimate; the runtime's limit and split/retry remain authoritative.
public enum TranslationPreflight {
    public static func fits(promptTokens: Int, sourceTokens: Int) -> Bool {
        guard (1...1536).contains(promptTokens), sourceTokens >= 0, sourceTokens <= promptTokens else { return false }
        // Count source separately: prompt instructions use context but are not translated.
        // Allow 50% token expansion plus formatting/EOG headroom without enlarging the context.
        let responseReserve = Int(ceil(Double(sourceTokens) * 1.5)) + 64
        return promptTokens + responseReserve <= 2048
    }
}
