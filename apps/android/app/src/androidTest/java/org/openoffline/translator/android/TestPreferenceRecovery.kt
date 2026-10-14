package org.openoffline.translator.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

/** Host cleanup after a thermal force-stop; never starts an Activity or model. */
@RunWith(AndroidJUnit4::class)
class TestPreferenceRecovery {
    @Test fun restorePreferencesAfterInterruptedUiTest() { UiTestEnvironment.restore() }
}
