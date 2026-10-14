import XCTest
@testable import OfflineCore
final class TranslationPromptTests: XCTestCase {
    func testRetired12BSelectionCannotLoadAgainAfterRestart() {
        XCTAssertEqual(TranslationModel.restoredSelection("mil-mmt46-12b-v1-q4km"), .index9B)
        XCTAssertEqual(TranslationModel.restoredSelection("qwen35-9b-q4km"), .index9B)
        XCTAssertEqual(TranslationModel.restoredSelection("mil-mmt46-4b-v1-q4km"), .index9B)
        XCTAssertEqual(TranslationModel.restoredSelection(nil), .index9B)
    }
    func testNewCandidatesUseSameRequestsAsScreening() {
        let qwen = TranslationModel.qwen9B.request(text: "Привет", source: .russian, target: .english)
        XCTAssertEqual(qwen.prefix, "<|im_start|>user\nTranslate the following text from Russian into English. Output only the translation, without explanations.\n\n")
        XCTAssertEqual(qwen.text, "Привет")
        XCTAssertEqual(qwen.suffix, "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
        for model in [TranslationModel.mil4B, .mil12B] {
            let request = model.request(text: "Привет <bos>", source: .russian, target: .thai)
            XCTAssertEqual(request.prefix, "")
            XCTAssertEqual(request.text, "Translate this from Russian to Thai:\nRussian: Привет <bos>\nThai:")
            XCTAssertEqual(request.suffix, "", "MiL must pass the whole raw completion as literal text, preserving token merges and avoiding BOS injection")
            XCTAssertTrue(model.requiresGemmaTerms)
        }
        XCTAssertFalse(TranslationModel.qwen9B.requiresGemmaTerms)
    }

    func testIndexUsesPublishedNonThinkingTemplateForEveryAppLanguage() {
        for language in SpeechLanguage.allCases {
            let prefix = TranslationModel.index9B.prefix(source: .russian, target: language)
            XCTAssertTrue(prefix.hasPrefix("<|im_start|>user\n请将以下文本翻译为"))
            XCTAssertFalse(prefix.contains("<bos>"))
            XCTAssertFalse(prefix.contains("fidelity"))
            XCTAssertTrue(prefix.hasSuffix("不要进行任何解释。\n\n"))
        }
        XCTAssertEqual(TranslationModel.index9B.prefix(source: .russian, target: .thai), "<|im_start|>user\n请将以下文本翻译为泰语，直接输出翻译结果，不要进行任何解释。\n\n")
        XCTAssertEqual(TranslationModel.index9B.suffix, "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
        XCTAssertEqual(TranslationModel.gemma4B.prefix(source: .russian, target: .english), TranslationPrompt.prefix(source: .russian, target: .english))
    }

    func testAndroidGoldenRequestsMatchApple() throws {
        struct Fixture: Decodable { let text: String; let target: String; let prefix: String; let suffix: String }
        struct Corpus: Decodable { let cases: [Fixture] }
        let root = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: root.appendingPathComponent("tests/fixtures/android/index-token-parity.json")))
        XCTAssertEqual(corpus.cases.count, 5)
        for fixture in corpus.cases {
            let target = try XCTUnwrap(SpeechLanguage(rawValue: fixture.target))
            let request = TranslationModel.index9B.request(text: fixture.text, source: .russian, target: target)
            XCTAssertEqual(request.prefix, fixture.prefix)
            XCTAssertEqual(request.text, fixture.text)
            XCTAssertEqual(request.suffix, fixture.suffix)
        }
    }

    func testRussianToEnglishGoldenTemplate() {
        XCTAssertEqual(TranslationPrompt.prefix(source: .russian, target: .english), "<bos><start_of_turn>user\nYou are a professional Russian (ru) to English (en) translator. Your goal is to accurately convey the meaning and nuances of the original Russian text while adhering to English grammar, vocabulary, and cultural sensitivities.\nProduce only the English translation, without any additional explanations or commentary. Please translate the following Russian text into English:\n\n\n")
        XCTAssertEqual(TranslationPrompt.suffix, "<end_of_turn>\n<start_of_turn>model\n")
    }
    func testEnglishToRussianGoldenTemplate() {
        XCTAssertEqual(TranslationPrompt.prefix(source: .english, target: .russian), "<bos><start_of_turn>user\nYou are a professional English (en) to Russian (ru) translator. Your goal is to accurately convey the meaning and nuances of the original English text while adhering to Russian grammar, vocabulary, and cultural sensitivities.\nProduce only the Russian translation, without any additional explanations or commentary. Please translate the following English text into Russian:\n\n\n")
    }
}
