import XCTest
@testable import OfflineCore

final class RecordingReconciliationTests: XCTestCase {
    private func block(_ source: String, _ translation: String) -> RecordingPreviewBlock {
        RecordingPreviewBlock(source: source, translation: translation)
    }
    func testUnchangedSentencesReuseTranslationsAndAudioPrefix() {
        let plan = RecordingReconciliation(finalText: "Hello. Do not cancel. Arrive at 6.30.", blocks: [
            block("Hello.", "Привет."), block("Do not cancel. Arrive at 6.30.", "Не отменяйте. Приедем в 6:30.")])
        XCTAssertEqual(plan.reusedBlocks, 2)
        XCTAssertTrue(plan.parts.allSatisfy { $0.translation != nil })
        XCTAssertEqual(plan.confirmedPrefix, "Привет. Не отменяйте. Приедем в 6:30.")
    }
    func testMidSentenceRepairRetranslatesWholeSentenceWithNeighbors() {
        let final = "Здравствуйте. Бронь на три ночи. Измените дату приезда, а количество ночей оставьте прежним. Спасибо. До свидания."
        let plan = RecordingReconciliation(finalText: final, blocks: [
            block("Здравствуйте.", "Hello."), block("Бронь на три ночи.", "Three nights."),
            block("Измените дату приезда.", "Change arrival."), block("А количество на чей оставьте прежним.", "BAD"),
            block("Спасибо.", "Thanks."), block("До свидания.", "Bye.")])
        XCTAssertEqual(plan.parts.map(\.source).joined(separator: " "), final)
        XCTAssertEqual(plan.parts.filter { $0.translation == nil }.map(\.source), ["Бронь на три ночи. Измените дату приезда, а количество ночей оставьте прежним. Спасибо."])
        XCTAssertEqual(plan.reusedBlocks, 2)
        XCTAssertEqual(plan.confirmedPrefix, "Hello.")
    }
    func testChangedNegationAndNumberInvalidatePrefix() {
        for final in ["Do not pay 50 euros.", "Pay 15 euros.", "Pay 50 euros?"] {
            let plan = RecordingReconciliation(finalText: final, blocks: [block("Pay 50 euros.", "OLD")])
            XCTAssertEqual(plan.reusedBlocks, 0)
            XCTAssertEqual(plan.confirmedPrefix, "")
        }
    }
    func testRepeatedSentenceIsAmbiguousAndNeverReusesWrongTranslation() {
        let plan = RecordingReconciliation(finalText: "Yes. No. Yes.", blocks: [block("Yes.", "OLD")])
        XCTAssertEqual(plan.reusedBlocks, 0)
        XCTAssertEqual(plan.parts.map(\.source).joined(separator: " "), "Yes. No. Yes.")
    }
    func testNewTailInvalidatesNeighborButDoesNotDropOrDuplicateText() {
        let plan = RecordingReconciliation(finalText: "First. Second. Third. Correction.", blocks: [block("First. Second.", "ONE TWO"), block("Third.", "THREE")])
        XCTAssertEqual(plan.confirmedPrefix, "ONE TWO")
        XCTAssertEqual(plan.parts.map(\.source), ["First. Second.", "Third. Correction."])
    }
    func testWhitespaceIsNormalizedButWordBoundariesArePreserved() {
        let same = RecordingReconciliation(finalText: "HELLO.\nWorld.", blocks: [block("Hello. World.", "OK")])
        XCTAssertEqual(same.reusedBlocks, 1)
        let different = RecordingReconciliation(finalText: "Notable.", blocks: [block("Not able.", "BAD")])
        XCTAssertEqual(different.reusedBlocks, 0)
    }
}
