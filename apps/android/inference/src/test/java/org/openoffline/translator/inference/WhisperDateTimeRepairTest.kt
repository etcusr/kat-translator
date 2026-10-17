package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class WhisperDateTimeRepairTest {
    private val original = "Поезд прибудет 22.18.16 октября."
    private val spoken = "Поезд прибудет двадцать два восемнадцать шестнадцатого октября."

    @Test fun defaultOffNeverRunsExtraDecode() {
        assertEquals(original, WhisperDateTimeRepair.apply(original, "ru", 16000) { error("Unexpected retry") })
    }
    @Test fun enabledConfirmsOrdinalAndPreservesPunctuation() {
        assertEquals("Поезд прибудет 22:18, 16 октября.", WhisperDateTimeRepair.apply(original, "ru", 30 * 16000, true) { spoken })
    }
    @Test fun ordinaryForeignLongMultipleOrIdentifierInputsNeverRetry() {
        for(text in listOf("Встреча 16.10.2026 в 22:18.", "Цена 22.18 рубля.", "Версия 22.18.16.",
            "Код 22.18.16 октября", "Встреча 99.18.16 октября", "Встреча 22.99.16 октября",
            "Встреча 22.18.31 апреля", "Встреча 22.18.30 февраля", "Встреча 122.18.16 октября",
            "Встреча 1.22.18.16 октября", "Поезд 22.18.16 октября, автобус 23.10.17 октября.")) {
            assertEquals(text, WhisperDateTimeRepair.apply(text, "ru", 16000, true) { error("Unexpected retry: $text") })
        }
        assertEquals(original, WhisperDateTimeRepair.apply(original, "en", 16000, true) { error("Unexpected retry") })
        assertEquals(original, WhisperDateTimeRepair.apply(original, "ru", 480001, true) { error("Unexpected retry") })
    }
    @Test fun mismatchedContextNumberMonthOrdinalAndLoopsKeepOriginal() {
        for(retry in listOf(spoken.replace("восемнадцать", "девятнадцать"), spoken.replace("Поезд", "Самолёт"),
            spoken.replace("октября", "ноября"), spoken.replace("шестнадцатого", "шестнадцать"),
            "$spoken Спасибо за просмотр.", "$spoken . . .")) {
            assertEquals(original, WhisperDateTimeRepair.apply(original, "ru", 16000, true) { retry })
        }
        val otherNumber = "Номер 214, приезд 22.18.16 октября."
        assertEquals(otherNumber, WhisperDateTimeRepair.apply(otherNumber, "ru", 16000, true) { "Номер двести четырнадцать, приезд двадцать два восемнадцать шестнадцатого октября." })
    }
    @Test fun zeroMinutesLeadingZeroCompoundOrdinalAndHyphenWork() {
        for((input, retry, expected) in listOf(
            Triple("Встреча в 9.00.31 января!", "Встреча в девять ноль тридцать первого января!", "Встреча в 9:00, 31 января!"),
            Triple("Приезжаю 0.05.4 МАЯ.", "Приезжаю ноль пять четвертого мая.", "Приезжаю 0:05, 4 МАЯ."),
            Triple("Встреча 9-05-31 января.", "Встреча девять ноль пять тридцать первого января.", "Встреча 9:05, 31 января."))) {
            assertEquals(expected, WhisperDateTimeRepair.apply(input, "ru", 16000, true) { retry })
        }
    }
    @Test fun failedRetryFallsBackAndLaterCallCanSucceed() {
        assertEquals(original, WhisperDateTimeRepair.apply(original, "ru", 16000, true) { throw IllegalStateException("Decoder failed") })
        assertEquals("Поезд прибудет 22:18, 16 октября.", WhisperDateTimeRepair.apply(original, "ru", 16000, true) { spoken })
    }
    @Test fun cancellationBeforeDuringAndAfterRetryPropagates() {
        for(stage in 0..2) {
            var cancelled = stage == 0
            try {
                WhisperDateTimeRepair.apply(original, "ru", 16000, true, { cancelled }) {
                    if(stage == 1)throw CancellationException()
                    cancelled = true
                    spoken
                }
                fail("Cancellation must propagate")
            } catch(_:CancellationException) { }
        }
        assertEquals("Поезд прибудет 22:18, 16 октября.", WhisperDateTimeRepair.apply(original, "ru", 16000, true) { spoken })
    }
}
