package org.openoffline.translator.android

/** Same sentence/word-first recursive partitioning as OfflineCore.TextSegments.
 * Keep every source character, never truncate or split a surrogate pair. */
object TextSegments {
    fun split(text: String, fits: (String) -> Boolean): List<String> {
        if (text.isEmpty()) return emptyList()
        if (fits(text)) return listOf(text)
        val (left, right) = bisect(text)
        return split(left, fits) + split(right, fits)
    }
    fun bisect(text: String): Pair<String, String> {
        val iterator = java.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
        iterator.setText(text)
        val boundaries = mutableListOf<Int>()
        var next = iterator.first()
        while (next != java.text.BreakIterator.DONE) { boundaries.add(next); next = iterator.next() }
        val count = boundaries.size - 1
        require(count > 1) { "A single character exceeds the model context" }
        val middle = count / 2
        val candidates = (1 until count).filter { kotlin.math.abs(it - middle) <= maxOf(1, count / 4) }
        val sentences = candidates.filter { text[boundaries[it] - 1] in ".!?\n。！？" }
        val words = candidates.filter { text[boundaries[it] - 1].isWhitespace() }
        val cut = (sentences.ifEmpty { words }).minByOrNull { kotlin.math.abs(it - middle) } ?: middle
        return text.substring(0, boundaries[cut]) to text.substring(boundaries[cut])
    }
}
