import XCTest
@testable import OfflineCore

final class TranslationProgressTests: XCTestCase {
    func testRetrySplitsWorkWithoutLosingTextOrRewindingCompletedCharacters() throws {
        let first = "Готово. "
        let remaining = "Первое предложение. Второе предложение."
        var work = TranslationWork(pieces: [first, remaining])
        XCTAssertEqual(work.current, first)
        work.completeCurrent()
        let before = work.progress
        XCTAssertEqual(before.completedCharacters, 8)
        XCTAssertEqual(before.fraction, 8.0 / 47.0, accuracy: 0.0001)
        try work.splitCurrent()
        XCTAssertEqual(work.progress.completedCharacters, 8)
        XCTAssertEqual(work.progress.totalCharacters, 47)
        XCTAssertEqual(work.progress.totalParts, 3)
        XCTAssertGreaterThan(work.progress.revision, before.revision)
        var tail = ""
        for _ in 0..<3 { if let part = work.current { tail += part; work.completeCurrent() } }
        XCTAssertEqual(tail, remaining)
        XCTAssertEqual(work.progress.fraction, 1)
        XCTAssertEqual(work.progress.completedParts, 3)
        XCTAssertNil(work.current)
    }
    func testProgressCountsSourceCharactersIncludingEmojiAndEmptyPieces() throws {
        var work = TranslationWork(pieces: ["", "👨‍👩‍👧‍👦я", " текст"])
        work.completeCurrent()
        XCTAssertEqual(work.progress.fraction, 0)
        work.completeCurrent()
        XCTAssertEqual(work.progress.completedCharacters, 2)
        XCTAssertEqual(work.progress.totalCharacters, 8)
        XCTAssertEqual(work.progress.fraction, 0.25)
        work.completeCurrent()
        XCTAssertEqual(work.progress.fraction, 1)
        work.completeCurrent()
        XCTAssertEqual(work.progress.completedCharacters, 8, "Completion after end must not overcount")
        var single = TranslationWork(pieces: ["я"])
        XCTAssertThrowsError(try single.splitCurrent())
        XCTAssertEqual(single.current, "я")
        XCTAssertEqual(single.progress.completedCharacters, 0)
    }
}
