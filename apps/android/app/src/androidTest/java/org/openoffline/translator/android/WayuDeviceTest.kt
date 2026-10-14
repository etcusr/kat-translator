package org.openoffline.translator.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.openoffline.translator.inference.WayuAssets

/** Real embedded CPython / shared Thai frontend; no voice weights or microphone needed. */
@RunWith(AndroidJUnit4::class)
class WayuDeviceTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    @Test fun sharedAppleThaiTokensMatchExactly() {
        assertArrayEquals(longArrayOf(0,53,162,76,158,58,7,53,162,63,56,171,53,162,60,43,58,172,0),WayuAssets.tokens(context,"ขอบคุณครับ"))
    }
    @Test fun embeddedEnglishPronunciationIsPreserved() {
        assertArrayEquals(longArrayOf(0,60,51,158,43,53,173,16,92,123,156,72,44,0),WayuAssets.tokens(context,"เรียก Grab"))
    }
    @Test fun numericNormalizationMatchesSpokenThai() {
        assertArrayEquals(WayuAssets.tokens(context,"ราคา สองร้อยห้าสิบ บาท"),WayuAssets.tokens(context,"ราคา 250 บาท"))
    }
    @Test fun unknownEnglishFailsWithoutDroppingWords() {
        val error=assertThrows(IllegalStateException::class.java){WayuAssets.tokens(context,"สวัสดี xyzqqzz")}
        assertTrue("Initialization failures must not masquerade as valid word rejection",error.message.orEmpty().contains("without dropping words"))
    }
}
