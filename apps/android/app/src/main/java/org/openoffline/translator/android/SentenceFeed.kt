package org.openoffline.translator.android

import java.util.concurrent.LinkedBlockingQueue

/** Hands finished sentences of a growing translation to speech while the model keeps writing.
 * Offered text is a prefix of the final output (greedy decoding only appends), so the spoken
 * pieces concatenate to the final translation. A sentence ends at terminal punctuation, optional
 * closing quotes/brackets and whitespace; pieces shorter than [minimum] wait for more text. */
internal class SentenceFeed(private val minimum: Int = 12) {
    private val queue = LinkedBlockingQueue<String>()
    private val end = String(charArrayOf('\u0000'))
    private var spoken = 0
    private var done = false

    @Synchronized fun offer(partial: String) {
        if (done || partial.length <= spoken) return
        val boundary = lastBoundary(partial, spoken)
        if (boundary < 0 || partial.substring(spoken, boundary).isBlank() || boundary - spoken < minimum) return
        emit(partial.substring(spoken, boundary)); spoken = boundary
    }

    /** Speaks whatever the final text adds after the already offered sentences, then ends the utterance. */
    @Synchronized fun finish(final: String) {
        if (done) return
        if (final.length > spoken) emit(final.substring(spoken))
        done = true; queue.add(end)
    }

    @Synchronized fun abort() { if (!done) { done = true; queue.clear(); queue.add(end) } }

    /** Blocks until the next sentence exists; ends after [finish] or [abort]. */
    fun sentences(): Sequence<String> = generateSequence { queue.take().takeUnless { it === end } }

    private fun emit(text: String) { if (text.isNotBlank()) queue.add(text.trim()) }

    companion object {
        private const val TERMINAL = ".!?…。！？"
        private const val CLOSING = ")]»\"'”’"
        internal fun lastBoundary(text: String, from: Int): Int {
            var result = -1
            for (index in from until text.length) {
                val c = text[index]
                if (c !in TERMINAL) continue
                var next = index + 1
                while (next < text.length && text[next] in CLOSING) next++
                // CJK full stops need no following space; others require one, which also skips decimals.
                if (next < text.length && (c in "。！？" || text[next].isWhitespace())) result = next
            }
            return result
        }
    }
}
