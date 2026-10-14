import XCTest
@testable import OfflineCore
final class BenchmarkRecorderTests: XCTestCase {
    func testPercentilesUseNearestRankAndIgnoreInvalidNumbers() {
        XCTAssertEqual(BenchmarkRecorder.percentile([5, 1, 4, 3, 2], fraction: 0.5), 3)
        XCTAssertEqual(BenchmarkRecorder.percentile([1, 2, 3, 4, 5], fraction: 0.95), 5)
        XCTAssertEqual(BenchmarkRecorder.percentile([.nan, 2, .infinity], fraction: 0.5), 2)
        XCTAssertNil(BenchmarkRecorder.percentile([], fraction: 0.95))
    }
    func testExportIncludesReproducibleMetadataWithoutSpeech() throws {
        var recorder = BenchmarkRecorder()
        recorder.append(BenchmarkSample(language: .russian, audioSeconds: 3, processingSeconds: 1,
            loadSeconds: 2, thermalState: "nominal"))
        let data = try recorder.exportJSON(device: "iPhone18,1", osVersion: "27.0.1")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["device"] as? String, "iPhone18,1")
        let samples = try XCTUnwrap(object["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0]["audioSeconds"] as? Double, 3)
        XCTAssertNil(samples[0]["audio"]); XCTAssertNil(samples[0]["text"]); XCTAssertNil(samples[0]["transcript"])
        XCTAssertNotNil(samples[0]["engineRevision"])
    }
}
