package org.openoffline.translator.inference

import java.text.BreakIterator
import java.util.Locale

/** Preserve every source character when fitting Marian's finite input/output context. */
object OpusSegments {
    private val boundary = Regex("[.!?][\"”»]?(\\s+)(?=[A-ZА-ЯЁІЇЄҐЎ\"“«])|(\\n\\s*\\n)")
    fun split(text: String, fits: (String) -> Boolean): List<String> {
        if (text.isEmpty()) return emptyList()
        val starts = mutableListOf(0)
        boundary.findAll(text).forEach { match ->
            val start = (match.groups[1] ?: match.groups[2])!!.range.first
            if (start > starts.last()) starts += start
        }
        starts += text.length
        fun fit(part: String): List<String> {
            if (fits(part)) return listOf(part)
            val (left, right) = bisect(part)
            return fit(left) + fit(right)
        }
        return starts.zipWithNext().flatMap { (start, end) -> fit(text.substring(start, end)) }
    }

    fun bisect(text: String): Pair<String, String> {
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(text) }
        val boundaries = mutableListOf<Int>()
        var next = iterator.first()
        while (next != BreakIterator.DONE) { boundaries += next; next = iterator.next() }
        val count = boundaries.size - 1
        require(count > 1) { "Text cannot fit the model without truncation" }
        val middle = count / 2
        val candidates = (1 until count).filter { kotlin.math.abs(it - middle) <= maxOf(1, count / 4) }
        val sentences = candidates.filter { text[boundaries[it] - 1] in ".!?\n。！？" }
        val words = candidates.filter { text[boundaries[it] - 1].isWhitespace() }
        val preferred = sentences.ifEmpty { words }
        val cut = boundaries[preferred.minByOrNull { kotlin.math.abs(it - middle) } ?: middle]
        return text.substring(0, cut) to text.substring(cut)
    }
}
