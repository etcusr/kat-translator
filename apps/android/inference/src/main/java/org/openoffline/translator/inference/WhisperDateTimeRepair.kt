package org.openoffline.translator.inference

import com.ibm.icu.text.RuleBasedNumberFormat
import java.util.Locale
import java.util.concurrent.CancellationException

/** Mirrors OfflineCore/WhisperDateTimeRepair: digits alone never establish time/day order. */
internal object WhisperDateTimeRepair {
    private val months = listOf("января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря")
    private val days = listOf(31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    private val pattern = Regex("(?<![\\p{L}\\p{N}.,:-])([0-9]{1,2})[.-]([0-9]{1,2})[.-]([0-9]{1,2})[ \\t]+(" + months.joinToString("|") + ")(?!\\p{L})", RegexOption.IGNORE_CASE)
    private val punctuationLoop = Regex("(?:[.!?,;:][ \\t]*){3,}")
    private val identifierWords = setOf("код", "версия", "номер", "артикул", "сборка", "идентификатор", "ip")
    private data class Candidate(val range: IntRange, val hour: Int, val minute: Int, val day: Int, val month: String)

    fun apply(original: String, language: String, sampleCount: Int, enabled: Boolean = false,
              isCancelled: () -> Boolean = { false }, retry: () -> String): String {
        if (!enabled || language != "ru" || sampleCount > 30 * 16000) return original
        val candidate = candidate(original) ?: return original
        fun guard() { if (isCancelled() || Thread.currentThread().isInterrupted) throw CancellationException("Speech recognition cancelled") }
        guard()
        val evidence = try { retry() } catch (e: CancellationException) { throw e }
            catch (_: IllegalStateException) { guard(); return original }
        guard()
        return repair(original, evidence, candidate)
    }

    private fun repair(original: String, retry: String, c: Candidate): String {
        if (retry.length > original.length * 3 + 80 || punctuationLoop.containsMatchIn(retry)) return original
        val formatter = RuleBasedNumberFormat(Locale.forLanguageTag("ru"), RuleBasedNumberFormat.SPELLOUT)
        val hour = formatter.format(c.hour.toLong())
        val minute = formatter.format(c.minute.toLong())
        val ordinal = RussianSpeechText.expandOrdinals("${c.day}-го")
        val minutes = if (c.minute < 10) listOf(minute, "ноль $minute") else listOf(minute)
        if (minutes.none { words(original.replaceRange(c.range, "$hour $it $ordinal ${c.month}")) == words(retry) }) return original
        return original.replaceRange(c.range, "${c.hour}:${c.minute.toString().padStart(2, '0')}, ${c.day} ${c.month}")
    }

    private fun candidate(text: String): Candidate? {
        val match = pattern.findAll(text).toList().singleOrNull() ?: return null
        val hour = match.groupValues[1].toInt()
        val minute = match.groupValues[2].toInt()
        val day = match.groupValues[3].toInt()
        val month = match.groupValues[4]
        val monthIndex = months.indexOf(month.lowercase(Locale.ROOT))
        if (hour >= 24 || minute >= 60 || day <= 0 || monthIndex < 0 || day > days[monthIndex]) return null
        if (words(text.substring(0, match.range.first)).lastOrNull() in identifierWords) return null
        return Candidate(match.range, hour, minute, day, month)
    }

    private fun words(text: String) = text.lowercase(Locale.ROOT).replace('ё', 'е')
        .split(Regex("[^\\p{L}\\p{N}]+" )).filter { it.isNotEmpty() }
}
