package org.openoffline.translator.inference
import org.junit.Assert.*
import org.junit.Test
class MmsSpeechTextTest {
    private val tokens="  0\nh 1\ne 2\nl 3\no 4\n"
    @Test fun canonicalCaseNormalization(){assertEquals("hello!",MmsSpeechText.prepare("Hello!",tokens,"la"))}
    @Test(expected=IllegalArgumentException::class)fun rejectForeignWords(){MmsSpeechText.prepare("Hello кот",tokens,"la")}
    @Test(expected=IllegalArgumentException::class)fun rejectUnverifiedNumberLanguage(){MmsSpeechText.prepare("12",tokens,"la")}
    @Test fun tamilNativeNumberPronunciation(){
        // ICU release-78.3 icu4c/source/data/rbnf/ta.txt, cardinal rule 12.
        val expected="பன்னிரண்டு"
        val tamil=expected.toSet().mapIndexed{index,letter->"$letter $index"}.joinToString("\n")
        assertEquals(expected,MmsSpeechText.prepare("12",tamil,"ta"))
    }
    @Test fun missingNativeNumberRulesNeverUseEnglishFallback(){
        for(language in listOf("bn","kn","pa","mr"))assertThrows(IllegalArgumentException::class.java){
            MmsSpeechText.prepare("12",tokens,language)
        }
    }
}
