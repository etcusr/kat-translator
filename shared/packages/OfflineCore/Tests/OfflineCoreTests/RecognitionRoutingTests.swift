import XCTest
@testable import OfflineCore

final class RecognitionRoutingTests: XCTestCase {
    func testRetiredAppleSelectionUsesClassicWhisperWithInstalledUltra() throws {
        let preference = RecognitionPreference.restoredSelection("apple")
        let classic = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let files = PipelineFiles(asr: classic, translation: classic, voices: [:],
                                  ultra: URL(fileURLWithPath: "/asr-parakeet-ultra"), recognitionPreference: preference)
        XCTAssertEqual(preference, .whisper)
        XCTAssertEqual(try files.recognitionURL(for: .russian), classic)
        XCTAssertEqual(try files.recognitionURL(for: nil), classic)
        XCTAssertFalse(RecognitionPreference.allCases.contains { $0.rawValue == "apple" })
    }
    func testRetiredSelectionMigratesToClassicAndIsNotOffered() {
        XCTAssertEqual(RecognitionPreference.restoredSelection("whisperKit"), .whisper)
        XCTAssertEqual(RecognitionPreference.restoredSelection("whisper"), .whisper)
        XCTAssertEqual(RecognitionPreference.restoredSelection("ultra"), .ultra)
        XCTAssertEqual(RecognitionPreference.restoredSelection(nil), .automatic)
        XCTAssertEqual(RecognitionPreference.allCases, [.automatic, .ultra, .whisper])
    }
    func testAutoUsesClassicEvenWithUltraInstalledAndPreservesMeta() throws {
        let classic = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let ultra = URL(fileURLWithPath: "/asr-parakeet-ultra", isDirectory: true)
        let omni = URL(fileURLWithPath: "/meta", isDirectory: true)
        let files = PipelineFiles(asr: classic, translation: classic, voices: [:], omnilingual: omni, ultra: ultra)
        for language: SpeechLanguage? in [nil, .russian, .english, .german, .spanish, .french, .lang_uk] {
            XCTAssertEqual(try files.recognitionURL(for: language), classic)
        }
        for language: SpeechLanguage in [.thai, .turkish, .chinese, .japanese, .lang_no, .lang_ca] {
            XCTAssertEqual(try files.recognitionURL(for: language), classic)
        }
        XCTAssertEqual(try files.recognitionURL(for: .lang_ban), omni)
        XCTAssertThrowsError(try files.recognitionURL(for: .lang_nrm))
        let missingUltra = PipelineFiles(asr: classic, translation: classic, voices: [:])
        XCTAssertEqual(try missingUltra.recognitionURL(for: .russian), classic)
        XCTAssertEqual(try missingUltra.recognitionURL(for: nil), classic)
        let onlyUltra = PipelineFiles(asr: nil, translation: classic, voices: [:], ultra: ultra)
        XCTAssertThrowsError(try onlyUltra.recognitionURL(for: nil))
        XCTAssertThrowsError(try onlyUltra.recognitionURL(for: .russian))
        XCTAssertThrowsError(try onlyUltra.recognitionURL(for: .thai))
    }
    func testManualRecognitionNeverSilentlyFallsBack() throws {
        let whisper = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let ultra = URL(fileURLWithPath: "/" + RecognitionCatalog.ultraID)
        let forced = PipelineFiles(asr: whisper, translation: whisper, voices: [:], ultra: ultra, recognitionPreference: .whisper)
        for language: SpeechLanguage? in [nil, .russian, .english, .thai] {
            XCTAssertEqual(try forced.recognitionURL(for: language), whisper)
        }
        XCTAssertThrowsError(try forced.recognitionURL(for: .lang_ban))
        let forcedUltra = PipelineFiles(asr: whisper, translation: whisper, voices: [:], ultra: ultra, recognitionPreference: .ultra)
        XCTAssertEqual(try forcedUltra.recognitionURL(for: nil), ultra)
        XCTAssertThrowsError(try forcedUltra.recognitionURL(for: .thai))
        for wrong in [nil, ultra, URL(fileURLWithPath: "/asr-whisperkit-turbo")] {
            XCTAssertThrowsError(try PipelineFiles(asr: wrong, translation: whisper, voices: [:], ultra: ultra,
                recognitionPreference: .whisper).recognitionURL(for: nil))
        }
    }
    func testOldDirectionsAndAutomaticKeepWhisper() throws {
        let whisper = URL(fileURLWithPath: "/whisper.bin")
        let omni = URL(fileURLWithPath: "/omni")
        let files = PipelineFiles(asr: whisper, translation: whisper, voices: [:], omnilingual: omni)
        XCTAssertEqual(try files.recognitionURL(for: .russian), whisper)
        XCTAssertEqual(try files.recognitionURL(for: nil), whisper)
        XCTAssertEqual(try files.recognitionURL(for: .lang_ban), omni)
        XCTAssertThrowsError(try files.recognitionURL(for: .lang_nrm))
    }
    func testMissingOptionalPackageDoesNotFallbackToWrongLanguage() {
        let url = URL(fileURLWithPath: "/whisper.bin")
        let files = PipelineFiles(asr: url, translation: url, voices: [:])
        XCTAssertThrowsError(try files.recognitionURL(for: .lang_ban))
        XCTAssertTrue(SpeechLanguage.lang_ban.supportsRecognition)
        XCTAssertFalse(SpeechLanguage.lang_sr_Latn.supportsRecognition)
        XCTAssertFalse(SpeechLanguage.lang_hi_Latn.supportsRecognition)
        XCTAssertEqual(RecognitionCatalog.omnilingualCodes["ban"], "ban_Latn")
    }
    /// The "download recognition" hint names the exact package the route would read (iPhone EN→RU without Whisper).
    func testMissingRecognitionHintNamesTheRoutedPackage() {
        let url = URL(fileURLWithPath: "/mt")
        let classic = URL(fileURLWithPath: "/Models/" + ModelDescriptor.turbo.id + ".bin")
        let empty = PipelineFiles(asr: nil, translation: url, voices: [:])
        XCTAssertEqual(empty.missingRecognitionPackage(for: .english), .whisper)
        XCTAssertEqual(empty.missingRecognitionPackage(for: nil), .whisper)
        XCTAssertEqual(empty.missingRecognitionPackage(for: .lang_ban), .omnilingual)
        XCTAssertNil(empty.missingRecognitionPackage(for: .lang_sr_Latn), "unsupported voice input is not a download")
        let whisperOnly = PipelineFiles(asr: classic, translation: url, voices: [:])
        XCTAssertNil(whisperOnly.missingRecognitionPackage(for: .russian))
        XCTAssertEqual(whisperOnly.missingRecognitionPackage(for: .lang_ban), .omnilingual)
        let ultra = PipelineFiles(asr: classic, translation: url, voices: [:], recognitionPreference: .ultra)
        XCTAssertEqual(ultra.missingRecognitionPackage(for: .russian), .ultra)
        XCTAssertNil(ultra.missingRecognitionPackage(for: .japanese))
        let manualWhisper = PipelineFiles(asr: URL(fileURLWithPath: "/other.bin"), translation: url, voices: [:], recognitionPreference: .whisper)
        XCTAssertEqual(manualWhisper.missingRecognitionPackage(for: .english), .whisper)
        for preference in RecognitionPreference.allCases {
            for language in SpeechLanguage.allCases.map(Optional.some) + [nil] {
                let files = PipelineFiles(asr: nil, translation: url, voices: [:], recognitionPreference: preference)
                let kind = RecognitionCatalog.package(for: language, preference: preference)
                XCTAssertEqual(files.missingRecognitionPackage(for: language), kind)
                if kind == nil { XCTAssertThrowsError(try files.recognitionURL(for: language)) }
            }
        }
    }
}

final class RecognitionChunksTests: XCTestCase {
    func testSplitsNearQuietPauseWithoutLosingOrDuplicatingSamples() {
        var audio = [Float](repeating: 0.5, count: 45_000)
        audio.replaceSubrange(18_000..<18_200, with: repeatElement(0, count: 200))
        let ranges = RecognitionChunks.ranges(samples: audio, sampleRate: 1000)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, audio.count)
        XCTAssertLessThan(ranges[0].upperBound, 19_000)
        XCTAssertEqual(ranges.reduce(0) { $0 + $1.count }, audio.count)
        for pair in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(pair.0.upperBound, pair.1.lowerBound) }
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 20_000 && !$0.isEmpty })
        XCTAssertTrue(RecognitionChunks.ranges(samples: [], sampleRate: 16000).isEmpty)
    }
}

final class ModelMemoryAdviceTests: XCTestCase {
    func testTwelveGBClassRecommendsIndexButNotQwenOrTwelveB() {
        let reported: UInt64 = 11_450_000_000
        XCTAssertTrue(ModelMemoryAdvice.recommended(.index9B, physicalMemory: reported))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.qwen9B, physicalMemory: reported))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.mil12B, physicalMemory: reported))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.mil12B, physicalMemory: 24_000_000_000))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.qwen9B, physicalMemory: 8_000_000_000))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.gemma4B, physicalMemory: 7_600_000_000))
        XCTAssertTrue(ModelMemoryAdvice.recommended(.opusBig, physicalMemory: 7_600_000_000))
        XCTAssertFalse(ModelMemoryAdvice.recommended(.gemma4B, physicalMemory: 4_000_000_000))
    }
}
