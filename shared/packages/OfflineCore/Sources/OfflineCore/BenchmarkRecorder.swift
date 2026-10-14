import Foundation
public struct BenchmarkSample: Codable, Sendable {
    public let language: SpeechLanguage
    public let audioSeconds: Double
    public let processingSeconds: Double
    public let inferenceSeconds: Double?
    public var realTimeFactor: Double? { audioSeconds > 0 ? processingSeconds / audioSeconds : nil }
    public let loadSeconds: Double?
    public let modelID: String
    public let modelRevision: String
    public let engineRevision: String
    public let thermalState: String
    public init(language: SpeechLanguage, audioSeconds: Double, processingSeconds: Double, loadSeconds: Double?, thermalState: String, inferenceSeconds: Double? = nil) {
        self.language = language; self.audioSeconds = audioSeconds; self.processingSeconds = processingSeconds
        self.loadSeconds = loadSeconds; self.thermalState = thermalState
        self.inferenceSeconds = inferenceSeconds
        modelID = ModelDescriptor.turbo.id; modelRevision = ModelDescriptor.revision
        engineRevision = "927cfce34f31707e17f2bff35c349632fb9e2c3a"
    }
}
public struct BenchmarkRecorder {
    public private(set) var samples: [BenchmarkSample] = []
    public init() {}
    public mutating func append(_ sample: BenchmarkSample) { samples.append(sample) }
    public func exportJSON(device: String, osVersion: String) throws -> Data {
        struct Summary: Codable {
            let language: String; let lengthRange: String; let count: Int
            let p50: Double?; let p95: Double?
        }
        struct Report: Codable {
            let device: String; let osVersion: String; let generatedAt: Date
            let samples: [BenchmarkSample]; let groups: [Summary]
        }
        func range(_ seconds: Double) -> String { seconds <= 5 ? "0-5s" : seconds <= 15 ? "5-15s" : "15-30s" }
        let groups = Dictionary(grouping: samples) { $0.language.rawValue + "|" + range($0.audioSeconds) }
        let summaries = groups.keys.sorted().map { key in
            let values = groups[key]!
            return Summary(language: values[0].language.rawValue, lengthRange: range(values[0].audioSeconds),
                count: values.count, p50: Self.percentile(values.map(\.processingSeconds), fraction: 0.5),
                p95: Self.percentile(values.map(\.processingSeconds), fraction: 0.95))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Report(device: device, osVersion: osVersion, generatedAt: Date(), samples: samples, groups: summaries))
    }
    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty, fraction.isFinite else { return nil }
        let index = max(0, min(sorted.count - 1, Int(ceil(max(0, min(1, fraction)) * Double(sorted.count))) - 1))
        return sorted[index]
    }
}
