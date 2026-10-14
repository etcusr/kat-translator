package org.openoffline.translator.inference

import com.ibm.icu.text.RuleBasedNumberFormat
import com.ibm.icu.util.ULocale
import java.math.BigDecimal
import java.text.Normalizer
import java.util.Locale

/** Same no-silent-word-dropping contract as OfflineCore/MMSSpeechText.swift. */
object MmsSpeechText {
    private val numberLanguages=setOf("ta","kn","gu","km","my","ky","pa","lo","fo","bn","he","mr")
    private val numberPattern=Regex("[0-9]+(?:[.,][0-9]+)?")
    fun prepare(text:String,tokens:String,language:String):String {
        val supported=tokens.lineSequence().mapNotNull{line->line.lastIndexOf(' ').takeIf{it>=0}?.let{line.substring(0,it)}}.toSet()
        var result=Normalizer.normalize(text,Normalizer.Form.NFC).lowercase(Locale.ROOT)
        result=numberPattern.replace(result){match->
            require(language in numberLanguages){"This voice cannot read these numbers; spell them out"}
            val formatter=RuleBasedNumberFormat(ULocale(language),RuleBasedNumberFormat.SPELLOUT)
            require(formatter.getLocale(ULocale.VALID_LOCALE).language==language){"Native number pronunciation is unavailable"}
            val value=BigDecimal(match.value.replace(',','.'))
            val words=try{formatter.format(value.longValueExact())}catch(_:ArithmeticException){
                val approximate=value.toDouble()
                require(approximate.isFinite()&&BigDecimal.valueOf(approximate).compareTo(value)==0){"Number cannot be pronounced exactly"}
                formatter.format(approximate)
            }
            require(words.none{Character.isDigit(it)}){"Number pronunciation is unavailable"}
            words.lowercase(Locale.ROOT)
        }
        var offset=0
        while(offset<result.length){val scalar=result.codePointAt(offset);val symbol=String(Character.toChars(scalar));val type=Character.getType(scalar)
            if(Character.isDigit(scalar))require(symbol in supported){"This voice cannot read these numbers; spell them out"}
            if(Character.isLetter(scalar)||type in setOf(Character.NON_SPACING_MARK.toInt(),Character.COMBINING_SPACING_MARK.toInt(),Character.ENCLOSING_MARK.toInt()))
                require(symbol in supported){"This voice does not support some letters; choose another voice"}
            offset+=Character.charCount(scalar)
        }
        return result
    }
}
