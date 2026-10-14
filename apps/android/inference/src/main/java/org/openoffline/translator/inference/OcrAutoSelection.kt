package org.openoffline.translator.inference

/** Model evidence, not language identification. Scores from different models are only a
 * conservative heuristic: ambiguous text requires an explicit source choice. */
object OcrAutoSelection {
    const val ENGLISH = "ppocr-v5-english"
    const val ESLAV = "ppocr-v5-eslav"
    val requiredModels = setOf(ENGLISH, ESLAV)
    data class Candidate(val modelId: String, val text: String, val confidence: Float)
    class Ambiguous(val candidates: List<Candidate>) : IllegalStateException("OCR source is ambiguous; choose a source language")

    /** Do not replace missing models with catalog ordering or infer a language from model id. */
    fun choose(candidates: List<Candidate>): Candidate? {
        require(candidates.isNotEmpty() && candidates.size <= 2 &&
            candidates.all { it.modelId in requiredModels } && candidates.map { it.modelId }.distinct().size == candidates.size)
        require(candidates.all { it.confidence.isFinite() && it.confidence in 0f..1f })
        val nonempty = candidates.filter { it.text.isNotBlank() }
        if (nonempty.isEmpty()) return null
        val ordered = nonempty.sortedByDescending { it.confidence }
        val best = ordered.first()
        if (best.confidence < .85f || best.text.none { it.isLetterOrDigit() }) throw Ambiguous(candidates)
        val runner = ordered.getOrNull(1)
        if (runner != null && normalized(best.text) != normalized(runner.text)) {
            val bestLength=best.text.count { it.isLetterOrDigit() }
            val runnerLength=runner.text.count { it.isLetterOrDigit() }
            // A wrong-script model can delete unsupported glyphs while retaining high
            // confidence for the remaining lookalikes. Mean token confidence alone hides
            // those deletions. A fuller hypothesis may break the tie only when it also
            // has substantially lower uncertainty; length by itself never wins.
            val fullerEvidence=best.confidence>=.90f && bestLength>=4 &&
                bestLength-runnerLength>=2 && runnerLength.toFloat()/bestLength<=.75f &&
                (1f-best.confidence)<=(1f-runner.confidence)*.75f
            if (bestLength<3 || (best.confidence-runner.confidence<.12f && !fullerEvidence)) throw Ambiguous(candidates)
        }
        return best
    }

    /** Average emitted CTC tokens only: padding blanks cannot inflate confidence. */
    fun decode(modelId: String, pairs: FloatArray, dictionary: List<String>): Candidate {
        require(pairs.size % 2 == 0)
        var previous = -1
        var sum = 0.0
        var count = 0
        val text = buildString {
            for (i in pairs.indices step 2) {
                val value = pairs[i]
                val id = value.toInt()
                val score = pairs[i + 1]
                require(value.isFinite() && value == id.toFloat() && id in dictionary.indices)
                require(score.isFinite() && score in 0f..1f)
                if (id != 0 && id != previous) { append(dictionary[id]); sum += score; count++ }
                previous = id
            }
        }.trim()
        return Candidate(modelId, text, if (count == 0) 0f else (sum / count).toFloat())
    }

    private fun normalized(text: String) = text.trim().replace(Regex("\\s+"), " ").lowercase(java.util.Locale.ROOT)
}
