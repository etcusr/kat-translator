package org.openoffline.translator.android
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.MmsSpeechText
@RunWith(AndroidJUnit4::class)
class MediaLanguageDeviceTest {
    @Test fun nativeTamilNumberPronunciation(){
        // Same pinned upstream Tamil cardinal rule as MmsSpeechTextTest.
        val expected="பன்னிரண்டு"
        val tokens=expected.toSet().mapIndexed{index,letter->"$letter $index"}.joinToString("\n")
        assertEquals(expected,MmsSpeechText.prepare("12",tokens,"ta"))
    }
    @Test fun rejectMissingBengaliRules(){assertThrows(IllegalArgumentException::class.java){MmsSpeechText.prepare("12","ব 0\nা 1\nর 2\nো 3\n","bn")}}
    @Test fun noEnglishFallbackForSmallLanguages(){assertThrows(IllegalArgumentException::class.java){MmsSpeechText.prepare("12","ব 0\nা 1\nর 2\nো 3\n","mn")}}
}
