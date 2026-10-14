package org.openoffline.translator.inference

import org.junit.Assert.*
import org.junit.Test

class OcrAutoSelectionTest {
    private fun en(text: String, score: Float) = OcrAutoSelection.Candidate(OcrAutoSelection.ENGLISH,text,score)
    private fun ru(text: String, score: Float) = OcrAutoSelection.Candidate(OcrAutoSelection.ESLAV,text,score)
    private fun ambiguous(vararg candidates: OcrAutoSelection.Candidate) {
        try { OcrAutoSelection.choose(candidates.toList()); fail("Ambiguity must not silently choose catalog order") }
        catch (_: OcrAutoSelection.Ambiguous) { }
    }

    @Test fun strongerEvidenceWinsIndependentlyOfCatalogOrderAndScript() {
        val english = listOf(ru("НЕLLO",.58f),en("HELLO",.98f))
        assertEquals("HELLO",OcrAutoSelection.choose(english)?.text)
        assertEquals(OcrAutoSelection.choose(english),OcrAutoSelection.choose(english.reversed()))
        assertEquals("ПРИВЕТ",OcrAutoSelection.choose(listOf(en("nPVBET",.64f),ru("ПРИВЕТ",.97f)))?.text)
    }

    @Test fun mixedScriptPageCanSelectADifferentModelPerBox() {
        val boxes = listOf(listOf(en("WELCOME",.99f),ru("WЕLСОМЕ",.70f)),
            listOf(en("nPHBET",.62f),ru("ПРИВЕТ",.99f)))
        assertEquals(listOf("WELCOME","ПРИВЕТ"),boxes.map { OcrAutoSelection.choose(it)?.text })
    }

    @Test fun conflictingConfidentCandidatesRequireAnExplicitSource() {
        ambiguous(en("PECTOPAH",.96f),ru("РЕСТОРАН",.95f))
        ambiguous(en("TO",.99f),ru("ТО",.70f))
        ambiguous(en("noise",.60f),ru("шум",.40f))
        ambiguous(en("...",.99f),ru("...",.98f))
    }

    @Test fun agreementAcceptsNumbersButDoesNotClaimALanguage() {
        val selected=OcrAutoSelection.choose(listOf(en("123 45",.98f),ru("123   45",.97f)))
        assertEquals("123 45",selected?.text)
    }

    @Test fun oneInstalledModelWorksWithinItsDisclosedCoverage() {
        assertEquals("HELLO",OcrAutoSelection.choose(listOf(en("HELLO",.97f)))?.text)
        ambiguous(ru("шум",.50f))
        assertNull(OcrAutoSelection.choose(listOf(en("",0f),ru("",0f))))
    }

    @Test fun paddingAndRepeatedTokensCannotInflateConfidence() {
        val decoded=OcrAutoSelection.decode(OcrAutoSelection.ENGLISH,
            floatArrayOf(0f,1f,1f,.80f,1f,.99f,0f,1f,1f,.60f,2f,1f),listOf("","A","B"))
        assertEquals("AAB",decoded.text)
        assertEquals(.80f,decoded.confidence,.0001f)
    }

    @Test fun wrongScriptDeletionNeedsBothFullerTextAndLowerUncertainty() {
        // Actual Pixel outputs for the same generated crop, retained as regression evidence.
        assertEquals("ПРИВЕТ МИР",OcrAutoSelection.choose(listOf(
            ru("ПРИВЕТ МИР",.9394511f),en("PBET MP",.89183354f)))?.text)
        // More text alone, or marginally lower uncertainty, cannot justify a choice.
        ambiguous(ru("ПРИВЕТ МИР",.94f),en("PBET MP",.939f))
        ambiguous(ru("ПРИВЕТ МИР",.89f),en("PBET MP",.91f))
        ambiguous(ru("ПРИВЕТ МИР",.94f),en("PRIVET MIR",.89f))
        ambiguous(ru("МНОГО ШУМА",.88f),en("MP",.81f))
        ambiguous(ru("ДОМ",.97f),en("DM",.91f))
    }

    @Test fun realMonospaceNearTieStaysAmbiguousInsteadOfForcingCyrillic() {
        ambiguous(en("Bctpeua 3abtpa",.8990104f),ru("Встреча завтра",.88896984f))
    }

    @Test fun caseOnlyAgreementDoesNotInventScriptDisagreement() {
        assertEquals("Hello World",OcrAutoSelection.choose(listOf(
            en("Hello World",.96f),ru("HELLO WORLD",.95f)))?.text)
    }

    @Test fun malformedOrUnknownEvidenceIsRejected() {
        val invalid=listOf<()->Unit>(
            { OcrAutoSelection.choose(emptyList()) },
            { OcrAutoSelection.choose(listOf(en("x",.9f),en("y",.8f))) },
            { OcrAutoSelection.choose(listOf(en("x",Float.NaN))) },
            { OcrAutoSelection.decode("x",floatArrayOf(1.5f,.9f),listOf("","x")) },
            { OcrAutoSelection.decode("x",floatArrayOf(1f,1.5f),listOf("","x")) })
        for(action in invalid) { try { action();fail("Invalid evidence accepted") } catch(_:IllegalArgumentException){} }
    }
}
