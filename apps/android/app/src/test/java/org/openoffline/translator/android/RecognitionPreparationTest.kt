package org.openoffline.translator.android

import org.junit.Assert.*
import org.junit.Test

class RecognitionPreparationTest {
    @Test fun onlySuccessfulCurrentSelectionBecomesReady() {
        val state=RecognitionPreparation()
        val ticket=state.begin("whisper:ru")
        assertFalse(state.isReady("whisper:ru"))
        assertTrue(state.complete(ticket))
        assertTrue(state.isReady("whisper:ru"))
        assertFalse(state.isReady("gigaam:ru"))
    }
    @Test fun leavingVoiceInvalidatesLoadedAndInflightSelection() {
        val state=RecognitionPreparation();val first=state.begin("whisper:ru")
        state.invalidate()
        assertFalse(state.complete(first));assertFalse(state.isReady("whisper:ru"))
        val second=state.begin("gigaam:ru");assertTrue(state.complete(second))
        state.invalidate();assertFalse(state.isReady("gigaam:ru"))
    }
    @Test fun oldCompletionCannotReplaceFastTabReturnOrLanguageChange() {
        val state=RecognitionPreparation();val old=state.begin("whisper:ru")
        state.invalidate();val latest=state.begin("parakeet:en")
        assertFalse(state.complete(old));assertFalse(state.isReady("whisper:ru"))
        assertTrue(state.complete(latest));assertTrue(state.isReady("parakeet:en"))
        assertFalse(state.complete(old));assertTrue(state.isReady("parakeet:en"))
    }
    @Test fun failedPreparationNeverPublishesReadinessAndRetryCanSucceed() {
        val state=RecognitionPreparation();state.begin("omnilingual:tr")
        state.invalidate();assertFalse(state.isReady("omnilingual:tr"))
        assertTrue(state.complete(state.begin("omnilingual:tr")))
        assertTrue(state.isReady("omnilingual:tr"))
    }
    @Test fun deferredReturnRequiresSameSelectionAndUnrevokedEpoch() {
        val state=RecognitionPreparation()
        state.defer("whisper:ru");assertFalse(state.consumeDeferred("gigaam:ru"))
        state.defer("whisper:ru");state.invalidate();assertFalse(state.consumeDeferred("whisper:ru"))
        state.defer("whisper:ru");state.cancelDeferred();assertFalse(state.consumeDeferred("whisper:ru"))
        state.defer("whisper:ru");assertTrue(state.consumeDeferred("whisper:ru"))
        assertFalse(state.consumeDeferred("whisper:ru"))
    }

}
