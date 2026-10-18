import XCTest
@testable import OfflineCore

final class ImageTextLayoutTests: XCTestCase {
    private func line(_ text: String, _ y: Double, x: Double = 0.02, width: Double = 0.9, height: Double = 0.18) -> ImageTextBlock {
        ImageTextBlock(text: text, box: ImageTextBox(x: x, y: y, width: width, height: height))
    }
    func testNarrowBannerKeepsEntireWrappedSentence() {
        let rows = [line("A museum opened in 2022", 0.30), line("and brings together art,", 0.50), line("science and technology.", 0.70, width: 0.6)]
        let result = ImageTextLayout.paragraphs(rows)
        XCTAssertEqual(result.map(\.text), ["A museum opened in 2022 and brings together art, science and technology."])
        XCTAssertEqual(result.first?.box.height ?? 0, 0.58, accuracy: 0.001)
    }
    func testHeadingAndParagraphGapStaySeparate() {
        let rows = [line("Museum notes", 0.02, width: 0.3, height: 0.08), line("The museum has two floors.", 0.2, height: 0.08), line("Tickets are sold upstairs.", 0.3, height: 0.08), line("Opening hours are seasonal.", 0.6, height: 0.08)]
        XCTAssertEqual(ImageTextLayout.paragraphs(rows).map(\.text), ["Museum notes", "The museum has two floors. Tickets are sold upstairs.", "Opening hours are seasonal."])
    }
    func testColumnsDoNotMerge() {
        let rows = [line("Left column", 0.1, width: 0.4, height: 0.05), line("Right column", 0.1, x: 0.55, width: 0.4, height: 0.05), line("Left next row", 0.17, width: 0.4, height: 0.05), line("Right next row", 0.17, x: 0.55, width: 0.4, height: 0.05)]
        let result = ImageTextLayout.paragraphs(rows)
        XCTAssertFalse(result.contains { $0.text.contains("Left") && $0.text.contains("Right") })
    }
    func testListItemsRemainSeparate() {
        for marker in ["•", "-", "1.", "2)"] {
            let result = ImageTextLayout.paragraphs([line(marker + " First item", 0.2), line(marker + " Second item", 0.4)])
            XCTAssertEqual(result.count, 2)
        }
    }
    func testFontSizeChangeDoesNotAbsorbHeading() {
        XCTAssertEqual(ImageTextLayout.paragraphs([line("A heading", 0.1, height: 0.15), line("Body text", 0.27, height: 0.07)]).count, 2)
    }
    func testLongParagraphIsNotSplitAtArbitraryCharacterLimit() {
        let a = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(ImageTextLayout.paragraphs([line(a, 0.2), line(a, 0.4)]).map(\.text), [a + " " + a])
    }
    func testDisplayRemovesOCRAndModelWhitespaceInsideEachParagraph() {
        let box = ImageTextBox(x: 0, y: 0, width: 1, height: 1)
        let blocks = [TranslatedImageBlock(original: "", translation: "  Heading \n", box: box), TranslatedImageBlock(original: "", translation: "  A sentence\n\n    continues\t here.  ", box: box)]
        XCTAssertEqual(ImageTextLayout.plainText(blocks), "Heading\n\nA sentence continues here.")
    }
    func testInsetQuoteDoesNotJoinTheArticle() {
        let result = ImageTextLayout.paragraphs([line("Quoted source...", 0.1, x: 0.044, height: 0.02), line("The article begins here.", 0.124, x: 0.022, height: 0.02)])
        XCTAssertEqual(result.map(\.text), ["Quoted source...", "The article begins here."])
    }
    func testGlyphHeightVariationDoesNotOrphanWrappedLines() {
        let result = ImageTextLayout.paragraphs([line("The report describes", 0.10, height: 0.02), line("changes across the", 0.124, height: 0.014), line("country.", 0.144, width: 0.3, height: 0.023)])
        XCTAssertEqual(result.map(\.text), ["The report describes changes across the country."])
    }
    func testShortFinalWordWithOnlyLowercaseGlyphsStaysInParagraph() {
        // OCR measures ink bounds: ascenders/descenders can make the preceding
        // line almost twice as tall as a short word made of lowercase glyphs.
        for smallHeight in [0.013, 0.014, 0.016] {
            let result = ImageTextLayout.paragraphs([
                line("Visitors must remain at a", 0.1, height: 0.025),
                line("distance.", 0.127, width: 0.17, height: smallHeight),
                line("21:00", 0.129, x: 0.8, width: 0.1, height: 0.017),
                line("A separate article starts here.", 0.2, height: 0.022)
            ])
            XCTAssertEqual(result.map(\.text), ["Visitors must remain at a distance.", "21:00", "A separate article starts here."])
        }
    }
    func testSeparateArticlesAndFooterStaySeparate() {
        let result = ImageTextLayout.paragraphs([line("First article continues", 0.1, height: 0.02), line("on another line.", 0.125, width: 0.5, height: 0.02), line("20:41", 0.126, x: 0.8, width: 0.1, height: 0.015), line("Second article begins", 0.22, height: 0.02), line("with a different subject.", 0.245, height: 0.02)])
        XCTAssertEqual(result.map(\.text), ["First article continues on another line.", "20:41", "Second article begins with a different subject."])
    }
    func testCJKWrappedTextDoesNotAcquireSpaces() {
        XCTAssertEqual(ImageTextLayout.paragraphs([line("博物館は", 0.2), line("毎日開いています。", 0.4)]).map(\.text), ["博物館は毎日開いています。"])
    }
}
