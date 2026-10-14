import XCTest
@testable import OfflineCore
final class PipelineBenchmarkTests: XCTestCase {
    func testDifferentTranslationModelsAreNotMergedIntoOneTimingGroup() throws {
        let samples = TranslationModel.allCases.map { model in
            var sample = PipelineBenchmark(source: .russian, inputKind: "text", inputMode: "text", audioSeconds: nil, thermalState: "nominal", memorySaving: true)
            sample.translationModelID = model.rawValue
            return sample
        }
        let data = try PipelineBenchmark.export(samples, device: "fixture", osVersion: "fixture")
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(report["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, samples.count)
        XCTAssertEqual(Set(groups.compactMap { $0["translationModelID"] as? String }), Set(samples.compactMap(\.translationModelID)))
    }

    func testReportHasOnlyExplicitMetricKeysAndSeparatesSpeechFromText() throws {
        var speech = PipelineBenchmark(source: .russian, inputKind: "speech", inputMode: "toggle", audioSeconds: 300, thermalState: "nominal", memorySaving: true)
        speech.voiceModelID = "voice-fixture"; speech.asrSeconds = 1; speech.mtSeconds = 2; speech.firstTokenSeconds = 0.5; speech.playbackScheduledSeconds = 4
        speech.asrLoadSeconds = 1; speech.mtLoadSeconds = 1; speech.ttsLoadSeconds = 1; speech.status = "completed"
        let text = PipelineBenchmark(source: .russian, inputKind: "text", inputMode: "text", audioSeconds: nil, thermalState: "nominal", memorySaving: false)
        let data = try PipelineBenchmark.export([speech, text], device: "fixture", osVersion: "fixture")
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(report.keys), ["schemaVersion", "device", "osVersion", "revisions", "samples", "groups"])
        let sample = try XCTUnwrap((report["samples"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(sample.keys), ["voiceModelID", "languageMode", "source", "inputKind", "inputMode", "audioSeconds", "thermalState", "memorySaving", "status", "totalSeconds", "ttsSeconds", "spokenSeconds", "asrSeconds", "mtSeconds", "firstTokenSeconds", "playbackScheduledSeconds", "asrLoadSeconds", "mtLoadSeconds", "ttsLoadSeconds", "mtFragments", "ttsFragments", "speechQueueWaitSeconds", "removedSilenceSeconds"])
        XCTAssertEqual((report["groups"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(speech.lengthRange, "180-300s"); XCTAssertEqual(text.lengthRange, "text")
    }
    func testEveryRecordingLengthBucket() {
        let values: [(Double, String)] = [(5,"0-5s"),(15,"5-15s"),(30,"15-30s"),(60,"30-60s"),(180,"60-180s"),(300,"180-300s"),(301,"300-600s"),(600,"300-600s"),(601,"600-1800s"),(1800,"600-1800s"),(1801,"1800s+")]
        for (duration, bucket) in values {
            XCTAssertEqual(PipelineBenchmark(source: .english, inputKind: "speech", inputMode: "hold", audioSeconds: duration, thermalState: "nominal", memorySaving: false).lengthRange, bucket)
        }
    }
    func testGroupsKeepDifferentVoicesAndMemoryModesSeparate() throws {
        var sample = PipelineBenchmark(source: .russian, inputKind: "text", inputMode: "text", audioSeconds: nil, thermalState: "nominal", memorySaving: false)
        sample.voiceModelID = "voice-a"
        var otherVoice = sample; otherVoice.voiceModelID = "voice-b"
        var otherMode = PipelineBenchmark(source: .russian, inputKind: "text", inputMode: "text", audioSeconds: nil, thermalState: "nominal", memorySaving: true)
        otherMode.voiceModelID = "voice-a"
        let data = try PipelineBenchmark.export([sample, sample, otherVoice, otherMode], device: "fixture", osVersion: "fixture")
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(report["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.compactMap { $0["count"] as? Int }.sorted(), [1, 1, 2])
        XCTAssertEqual(Set(groups.compactMap { $0["voiceModelID"] as? String }), ["voice-a", "voice-b"])
    }
    func testAutomaticReportsUseResolvedDirectionAndKeepFailuresUnknown() throws {
        var detected = PipelineBenchmark(source: nil, inputKind: "speech", inputMode: "toggle", audioSeconds: 5, thermalState: "nominal", memorySaving: false)
        detected.source = .english; detected.status = "completed"
        var manual = PipelineBenchmark(source: .english, inputKind: "speech", inputMode: "toggle", audioSeconds: 5, thermalState: "nominal", memorySaving: false)
        manual.status = "completed"
        var failed = PipelineBenchmark(source: nil, inputKind: "speech", inputMode: "toggle", audioSeconds: 5, thermalState: "nominal", memorySaving: false)
        failed.status = "failed"
        let data = try PipelineBenchmark.export([detected, manual, failed], device: "fixture", osVersion: "fixture")
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(report["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 3, "Automatic and manual timings must not be merged")
        let samples = try XCTUnwrap(report["samples"] as? [[String: Any]])
        XCTAssertEqual(samples[0]["source"] as? String, "en")
        XCTAssertEqual(samples[0]["languageMode"] as? String, "auto")
        XCTAssertNil(samples[2]["source"])
        XCTAssertTrue(groups.contains { ($0["direction"] as? String) == "unknown" && ($0["status"] as? String) == "failed" })
    }
}
