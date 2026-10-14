package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test
import java.io.File

class MissingVoiceTest {
    @Test fun absentVoiceCarriesExactLanguageAndPackageForDownloadInsteadOfGenericModelError() {
        val error=assertThrows(MissingVoiceException::class.java) { requireVoicePath("selected-english-voice","en","voice",null) }
        assertEquals(MissingVoice("en","selected-english-voice","voice"),error.request)
    }
    @Test fun installedVoiceIsReturnedWithoutDownloadRequest() {
        val path=File("installed-voice")
        assertSame(path,requireVoicePath("selected-voice","en","text",path))
    }
}
