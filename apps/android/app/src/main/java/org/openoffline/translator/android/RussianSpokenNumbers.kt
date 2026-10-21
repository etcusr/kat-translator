package org.openoffline.translator.android

/**
 * Inverse normalization for unpunctuated Russian ASR output (GigaAM writes numbers as words).
 * Only unambiguous date, year and clock patterns become digits, matching what Whisper writes:
 * "двадцать третьего марта" → "23 марта", "две тысячи двадцать седьмого года" → "2027 года",
 * "в семь сорок пять" → "в 7:45", "до двадцати одного часа" → "до 21 часа".
 * Other numbers, "половина восьмого" and "без четверти девять" stay as spoken.
 */
object RussianSpokenNumbers {
    private enum class Kind { UNIT, TEEN, TEN, HUNDRED, THOUSAND }
    private data class Word(val value: Int, val kind: Kind, val ordinal: Boolean)

    private val words: Map<String, Word> = buildMap {
        fun cardinal(value: Int, kind: Kind, vararg forms: String) = forms.forEach { put(it, Word(value, kind, false)) }
        cardinal(0, Kind.UNIT, "ноль", "нуля", "нулю", "нулём", "нулем", "нуле")
        cardinal(1, Kind.UNIT, "один", "одного", "одному", "одним", "одном", "одна", "одной", "одну", "одно")
        cardinal(2, Kind.UNIT, "два", "две", "двух", "двум", "двумя")
        cardinal(3, Kind.UNIT, "три", "трёх", "трех", "трём", "трем", "тремя")
        cardinal(4, Kind.UNIT, "четыре", "четырёх", "четырех", "четырём", "четырем", "четырьмя")
        cardinal(5, Kind.UNIT, "пять", "пяти", "пятью")
        cardinal(6, Kind.UNIT, "шесть", "шести", "шестью")
        cardinal(7, Kind.UNIT, "семь", "семи", "семью")
        cardinal(8, Kind.UNIT, "восемь", "восьми", "восемью", "восьмью")
        cardinal(9, Kind.UNIT, "девять", "девяти", "девятью")
        listOf("десят", "одиннадцат", "двенадцат", "тринадцат", "четырнадцат", "пятнадцат", "шестнадцат", "семнадцат", "восемнадцат", "девятнадцат")
            .forEachIndexed { i, stem -> cardinal(10 + i, Kind.TEEN, stem + "ь", stem + "и", stem + "ью") }
        cardinal(20, Kind.TEN, "двадцать", "двадцати", "двадцатью"); cardinal(30, Kind.TEN, "тридцать", "тридцати", "тридцатью")
        cardinal(40, Kind.TEN, "сорок", "сорока"); cardinal(50, Kind.TEN, "пятьдесят", "пятидесяти", "пятьюдесятью")
        cardinal(60, Kind.TEN, "шестьдесят", "шестидесяти", "шестьюдесятью"); cardinal(70, Kind.TEN, "семьдесят", "семидесяти", "семьюдесятью")
        cardinal(80, Kind.TEN, "восемьдесят", "восьмидесяти", "восемьюдесятью"); cardinal(90, Kind.TEN, "девяносто", "девяноста")
        cardinal(100, Kind.HUNDRED, "сто", "ста"); cardinal(200, Kind.HUNDRED, "двести", "двухсот", "двумстам")
        cardinal(300, Kind.HUNDRED, "триста", "трёхсот", "трехсот"); cardinal(400, Kind.HUNDRED, "четыреста", "четырёхсот", "четырехсот")
        cardinal(500, Kind.HUNDRED, "пятьсот", "пятисот"); cardinal(600, Kind.HUNDRED, "шестьсот", "шестисот")
        cardinal(700, Kind.HUNDRED, "семьсот", "семисот"); cardinal(800, Kind.HUNDRED, "восемьсот", "восьмисот")
        cardinal(900, Kind.HUNDRED, "девятьсот", "девятисот")
        cardinal(1000, Kind.THOUSAND, "тысяча", "тысячи", "тысяч", "тысячу", "тысячей", "тысячам")
        val hard = listOf("ый", "ой", "ого", "ому", "ым", "ом", "ая", "ую", "ое", "ые", "ых", "ыми")
        val soft = listOf("ий", "его", "ему", "им", "ем", "яя", "юю", "ее", "ие", "их", "ими")
        fun ordinal(value: Int, kind: Kind, stem: String, endings: List<String> = hard) = endings.forEach { put(stem + it, Word(value, kind, true)) }
        ordinal(1, Kind.UNIT, "перв"); ordinal(2, Kind.UNIT, "втор")
        listOf("ий", "ьего", "ьему", "ьим", "ьем", "ья", "ью", "ье", "ьи", "ьих", "ьими").forEach { put("трет$it", Word(3, Kind.UNIT, true)) }
        ordinal(4, Kind.UNIT, "четвёрт"); ordinal(4, Kind.UNIT, "четверт"); ordinal(5, Kind.UNIT, "пят"); ordinal(6, Kind.UNIT, "шест")
        ordinal(7, Kind.UNIT, "седьм"); ordinal(8, Kind.UNIT, "восьм"); ordinal(9, Kind.UNIT, "девят")
        listOf("десят", "одиннадцат", "двенадцат", "тринадцат", "четырнадцат", "пятнадцат", "шестнадцат", "семнадцат", "восемнадцат", "девятнадцат")
            .forEachIndexed { i, stem -> ordinal(10 + i, Kind.TEEN, stem) }
        ordinal(20, Kind.TEN, "двадцат"); ordinal(30, Kind.TEN, "тридцат"); ordinal(40, Kind.TEN, "сороков"); ordinal(50, Kind.TEN, "пятидесят")
        ordinal(60, Kind.TEN, "шестидесят"); ordinal(70, Kind.TEN, "семидесят"); ordinal(80, Kind.TEN, "восьмидесят"); ordinal(90, Kind.TEN, "девяност")
        ordinal(1000, Kind.THOUSAND, "тысячн")
    }
    private val months = setOf("января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря")
    private val yearWords = setOf("год", "года", "году", "годом")
    private val hourWords = setOf("час", "часа", "часов", "часам", "часу")
    private val timePrepositions = setOf("в", "во", "до", "с", "со", "после", "к", "ко", "около", "от", "по")
    // "в половине восьмого", "в начале девятого": ordinal hours, not days.
    private val clockOrdinals = setOf("половине", "половина", "пол", "начале", "конце", "четверти", "часу")
    private val dateForms = Regex(".*(ого|его|ое|ее|ье|ьего|ым|ом|ем)$")

    private fun ordinalEnding(word: String) = when {
        word.endsWith("го") -> "го"; word.endsWith("е") -> "е"; word.endsWith("м") -> "м"; else -> "й"
    }
    /** A parsed number spanning tokens [start, end). */
    private data class Number(val start: Int, val end: Int, val value: Int, val ordinal: Boolean, val last: String)

    fun normalize(text: String): String {
        val tokens = text.split(' ').filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return text
        val lower = tokens.map { it.lowercase().trimEnd(',', '.', '!', '?', ';', ':') }
        val numbers = parse(lower)
        if (numbers.isEmpty()) return text
        val replace = sortedMapOf<Int, Pair<Int, String>>() // start -> (end, replacement)
        val hasMonth = lower.any { it in months }
        var i = 0
        while (i < numbers.size) {
            val n = numbers[i]
            val next = lower.getOrNull(n.end)
            val previous = lower.getOrNull(n.start - 1)
            val following = numbers.getOrNull(i + 1)?.takeIf { it.start == n.end }
            when {
                // Day of month: "двадцать третьего марта", also "с первого по десятое ноября", "выезд двадцать первого".
                n.ordinal && n.value in 1..31 && next in months -> replace[n.start] = n.end to n.value.toString()
                // Without a following month the ending stays ("21-го"), otherwise a bare number reads as an hour.
                n.ordinal && n.value in 1..31 && hasMonth && dateForms.matches(n.last) && previous !in clockOrdinals ->
                    replace[n.start] = n.end to "${n.value}-${ordinalEnding(n.last)}"
                // Year: "две тысячи двадцать седьмого года".
                n.ordinal && n.value in 1000..2999 && next in yearWords -> replace[n.start] = n.end to n.value.toString()
                // Clock: preposition + hour + minutes ("в семь сорок пять", "с пятнадцати ноль ноль").
                !n.ordinal && n.value in 0..23 && previous in timePrepositions && following != null && !following.ordinal -> {
                    var minutes = following.value; var end = following.end; var used = 1
                    val second = numbers.getOrNull(i + 2)?.takeIf { it.start == following.end && !it.ordinal }
                    if (following.value == 0 && second != null && second.value in 0..9) { minutes = second.value; end = second.end; used = 2 }
                    if (minutes in 0..59 && (following.value != 0 || used == 2)) {
                        replace[n.start] = end to "${n.value}:${minutes.toString().padStart(2, '0')}"; i += used
                    }
                }
                // Hour count after a time preposition: "после четырнадцати часов", "до двадцати одного часа".
                !n.ordinal && n.value in 0..24 && next in hourWords && previous in timePrepositions -> replace[n.start] = n.end to n.value.toString()
                // Range start: "с девяти до двадцати одного часа".
                !n.ordinal && n.value in 0..24 && previous in setOf("с", "со", "от") && next == "до" &&
                    numbers.getOrNull(i + 1)?.let { it.start == n.end + 1 && !it.ordinal && lower.getOrNull(it.end) in hourWords } == true ->
                    replace[n.start] = n.end to n.value.toString()
            }
            i++
        }
        if (replace.isEmpty()) return text
        val out = mutableListOf<String>(); var index = 0
        while (index < tokens.size) {
            val hit = replace[index]
            if (hit == null) { out += tokens[index]; index++; continue }
            val (end, value) = hit
            // Keep punctuation attached to the last replaced word.
            val tail = tokens[end - 1].drop(tokens[end - 1].trimEnd(',', '.', '!', '?', ';', ':').length)
            out += value + tail; index = end
        }
        return out.joinToString(" ")
    }

    /** Greedy left-to-right parse; magnitudes must decrease, an ordinal ends a number. */
    private fun parse(lower: List<String>): List<Number> {
        val result = mutableListOf<Number>()
        var i = 0
        while (i < lower.size) {
            val first = words[lower[i]]
            if (first == null) { i++; continue }
            var total = 0; var current = 0; var j = i; var ordinal = false; var lastKind: Kind? = null
            while (j < lower.size) {
                val w = words[lower[j]] ?: break
                val allowed = when (w.kind) {
                    Kind.THOUSAND -> total == 0 && (lastKind == null || lastKind == Kind.UNIT || lastKind == Kind.TEEN || lastKind == Kind.TEN || lastKind == Kind.HUNDRED)
                    Kind.HUNDRED -> lastKind == null || lastKind == Kind.THOUSAND
                    Kind.TEN -> lastKind == null || lastKind == Kind.THOUSAND || lastKind == Kind.HUNDRED
                    Kind.TEEN -> lastKind == null || lastKind == Kind.THOUSAND || lastKind == Kind.HUNDRED
                    Kind.UNIT -> lastKind == null || lastKind == Kind.THOUSAND || lastKind == Kind.HUNDRED || lastKind == Kind.TEN
                }
                if (!allowed) break
                // "ноль" never starts a compound with other words except as minutes ("ноль ноль", "ноль пять").
                if (w.value == 0 && lastKind != null) break
                if (w.kind == Kind.THOUSAND) { total = (if (current == 0) 1 else current) * 1000; current = 0 } else current += w.value
                lastKind = w.kind; j++
                if (w.ordinal) { ordinal = true; break }
                if (w.value == 0) break
            }
            if (j == i) { i++; continue }
            result += Number(i, j, total + current, ordinal, lower[j - 1]); i = j
        }
        return result
    }
}
