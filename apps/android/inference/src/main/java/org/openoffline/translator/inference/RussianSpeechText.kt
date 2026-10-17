package org.openoffline.translator.inference

/**
 * Russian speech text: ordinals written with a hyphenated ending ("16-е", "15-го", "2026-м")
 * are spelled out before synthesis when their grammatical form is known.
 * Ambiguous abbreviations are preserved unless adjacent words resolve them.
 * Mirrors the Apple implementation (OfflineCore/RussianSpeechText.swift) and its test cases.
 */
object RussianSpeechText {
    private enum class Form {
        MASCULINE, GENITIVE, DATIVE, PREPOSITIONAL, INSTRUMENTAL, NEUTER,
        FEMININE, FEMININE_ACCUSATIVE, FEMININE_OBLIQUE, PLURAL, PLURAL_GENITIVE, PLURAL_INSTRUMENTAL,
        AMBIGUOUS_Y, AMBIGUOUS_M, AMBIGUOUS_E
    }
    private val endings = listOf(
        "ыми" to Form.PLURAL_INSTRUMENTAL, "ими" to Form.PLURAL_INSTRUMENTAL, "ми" to Form.PLURAL_INSTRUMENTAL,
        "ого" to Form.GENITIVE, "его" to Form.GENITIVE, "го" to Form.GENITIVE,
        "ому" to Form.DATIVE, "ему" to Form.DATIVE, "му" to Form.DATIVE,
        "ый" to Form.MASCULINE, "ий" to Form.MASCULINE, "ой" to Form.AMBIGUOUS_Y, "й" to Form.AMBIGUOUS_Y,
        "ым" to Form.INSTRUMENTAL, "им" to Form.INSTRUMENTAL, "ом" to Form.PREPOSITIONAL, "ем" to Form.PREPOSITIONAL, "м" to Form.AMBIGUOUS_M,
        "ое" to Form.NEUTER, "ее" to Form.NEUTER, "е" to Form.AMBIGUOUS_E,
        "ые" to Form.PLURAL, "ие" to Form.PLURAL, "и" to Form.PLURAL,
        "ая" to Form.FEMININE, "яя" to Form.FEMININE, "я" to Form.FEMININE,
        "ую" to Form.FEMININE_ACCUSATIVE, "юю" to Form.FEMININE_ACCUSATIVE, "ю" to Form.FEMININE_ACCUSATIVE,
        "ых" to Form.PLURAL_GENITIVE, "их" to Form.PLURAL_GENITIVE, "х" to Form.PLURAL_GENITIVE
    )
    private val stems = mapOf(
        1 to "перв", 2 to "втор", 3 to "трет", 4 to "четвёрт", 5 to "пят", 6 to "шест", 7 to "седьм", 8 to "восьм", 9 to "девят",
        10 to "десят", 11 to "одиннадцат", 12 to "двенадцат", 13 to "тринадцат", 14 to "четырнадцат", 15 to "пятнадцат",
        16 to "шестнадцат", 17 to "семнадцат", 18 to "восемнадцат", 19 to "девятнадцат", 20 to "двадцат", 30 to "тридцат",
        40 to "сороков", 50 to "пятидесят", 60 to "шестидесят", 70 to "семидесят", 80 to "восьмидесят", 90 to "девяност",
        100 to "сот", 200 to "двухсот", 300 to "трёхсот", 400 to "четырёхсот", 500 to "пятисот", 600 to "шестисот",
        700 to "семисот", 800 to "восьмисот", 900 to "девятисот"
    )
    private val stressed = setOf(2, 6, 7, 8, 40)
    private val pattern = Regex("(?<![0-9.,])([0-9]{1,4})-(" + endings.joinToString("|") { it.first } + ")(?![А-Яа-яЁё0-9])")

    // Bounded vocabulary, identical to Apple: suffix-only guesses misclassify words such as "линии".
    private val masculineNouns = setOf(
        "этаж", "раз", "рейс", "класс", "день", "год", "номер", "пункт", "дом", "час",
        "поезд", "вагон", "путь", "вариант", "том", "вопрос", "приз", "квартал", "месяц"
    )
    private val feminineObliqueNouns = setOf(
        "улицы", "улице", "улицей", "остановки", "остановке", "остановкой",
        "станции", "станцией", "линии", "линией", "школы", "школе", "школой",
        "страницы", "странице", "страницей", "попытки", "попытке", "попыткой",
        "недели", "неделе", "неделей", "главы", "главе", "главой"
    )
    private val neuterNouns = setOf("число", "место", "окно", "здание", "задание", "упражнение")
    private val pluralNouns = setOf(
        "годы", "дни", "места", "числа", "этажи", "рейсы", "классы", "номера", "дома",
        "страницы", "улицы", "школы", "станции", "линии", "недели", "окна", "здания", "задания", "упражнения"
    )
    private val months = setOf(
        "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
        "сентября", "октября", "ноября", "декабря"
    )

    fun expandOrdinals(text: String): String {
        val result = StringBuilder(text)
        for (match in pattern.findAll(text).toList().reversed()) {
            val number = match.groupValues[1].toIntOrNull() ?: continue
            val candidate = endings.firstOrNull { it.first == match.groupValues[2] }?.second ?: continue
            val form = resolve(candidate, number, text.substring(0, match.range.first), text.substring(match.range.last + 1)) ?: continue
            val words = ordinal(number, form) ?: continue
            result.replace(match.range.first, match.range.last + 1, words)
        }
        return result.toString()
    }

    private fun resolve(form: Form, number: Int, before: String, after: String): Form? {
        // Do not infer agreement across punctuation, intervening adjectives, or a newline.
        val following = after.dropWhile { it == ' ' || it == '\t' }
        val nextWord = following.takeWhile { it.isLetter() }.lowercase()
        return when (form) {
            Form.AMBIGUOUS_Y -> when {
                nextWord in feminineObliqueNouns -> Form.FEMININE_OBLIQUE
                nextWord in masculineNouns -> Form.MASCULINE
                else -> null
            }
            Form.AMBIGUOUS_M -> {
                if (nextWord.isEmpty() || nextWord in setOf("и", "или", "а", "но")) return null
                val preposition = before.dropLastWhile { it == ' ' || it == '\t' }.takeLastWhile { it.isLetter() }.lowercase()
                when (preposition) {
                    "в", "во", "на", "о", "об", "обо", "при" -> Form.PREPOSITIONAL
                    "перед", "пред", "над", "под", "за", "с", "со", "между" -> Form.INSTRUMENTAL
                    else -> null
                }
            }
            Form.AMBIGUOUS_E -> when {
                nextWord in pluralNouns -> Form.PLURAL
                nextWord in neuterNouns -> Form.NEUTER
                number !in 1..31 -> null
                nextWord in months -> Form.NEUTER
                // Conventional day-of-month reading of bare "16-е", including "17-е, а не 16-е".
                following.isEmpty() || following.first() in ".,;:!?" -> Form.NEUTER
                else -> null
            }
            else -> form
        }
    }

    private fun ordinal(number: Int, form: Form): String? {
        if (number <= 0 || number >= 10_000) return null
        val thousands = number / 1000 * 1000; val hundreds = number % 1000 / 100 * 100; val rest = number % 100
        val prefix = mutableListOf<Int>(); val last: Int
        if (rest == 0) {
            if (hundreds == 0) return null // "2000-й" needs compound stems; leave it for the voice.
            last = hundreds
        } else if (rest < 20 || rest % 10 == 0) {
            if (hundreds > 0) prefix += hundreds
            last = rest
        } else {
            if (hundreds > 0) prefix += hundreds
            prefix += rest / 10 * 10; last = rest % 10
        }
        val stem = stems[last] ?: return null
        val cardinals = (if (thousands > 0) listOf(cardinal(thousands)) else emptyList()) + prefix.map(::cardinal)
        if (cardinals.any { it == null }) return null
        return (cardinals.filterNotNull() + (stem + ending(form, soft = last == 3, stressed = last in stressed))).joinToString(" ")
    }

    // Only whole thousands, hundreds and tens reach here; avoids locale-dependent spell-out.
    private fun cardinal(value: Int): String? = when {
        value >= 1000 -> {
            val n = value / 1000
            when (n) { 1 -> "тысяча"; 2 -> "две тысячи"; 3 -> "три тысячи"; 4 -> "четыре тысячи"
                5 -> "пять тысяч"; 6 -> "шесть тысяч"; 7 -> "семь тысяч"; 8 -> "восемь тысяч"; 9 -> "девять тысяч"; else -> null }
        }
        value >= 100 -> listOf("сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот").getOrNull(value / 100 - 1)
        else -> mapOf(20 to "двадцать", 30 to "тридцать", 40 to "сорок", 50 to "пятьдесят", 60 to "шестьдесят",
            70 to "семьдесят", 80 to "восемьдесят", 90 to "девяносто")[value]
    }

    private fun ending(form: Form, soft: Boolean, stressed: Boolean): String = if (soft) when (form) {
        Form.MASCULINE -> "ий"; Form.GENITIVE -> "ьего"; Form.DATIVE -> "ьему"; Form.PREPOSITIONAL -> "ьем"
        Form.INSTRUMENTAL -> "ьим"; Form.NEUTER -> "ье"; Form.FEMININE -> "ья"; Form.FEMININE_ACCUSATIVE -> "ью"
        Form.FEMININE_OBLIQUE -> "ьей"; Form.PLURAL -> "ьи"; Form.PLURAL_GENITIVE -> "ьих"; Form.PLURAL_INSTRUMENTAL -> "ьими"
        else -> error("Unresolved ordinal form")
    } else when (form) {
        Form.MASCULINE -> if (stressed) "ой" else "ый"; Form.GENITIVE -> "ого"; Form.DATIVE -> "ому"; Form.PREPOSITIONAL -> "ом"
        Form.INSTRUMENTAL -> "ым"; Form.NEUTER -> "ое"; Form.FEMININE -> "ая"; Form.FEMININE_ACCUSATIVE -> "ую"
        Form.FEMININE_OBLIQUE -> "ой"; Form.PLURAL -> "ые"; Form.PLURAL_GENITIVE -> "ых"; Form.PLURAL_INSTRUMENTAL -> "ыми"
        else -> error("Unresolved ordinal form")
    }
}
