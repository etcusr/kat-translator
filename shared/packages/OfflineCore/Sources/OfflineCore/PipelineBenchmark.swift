import Foundation
public struct PipelineBenchmark: Codable, Sendable {
    public var source: SpeechLanguage?
    public var target: SpeechLanguage?
    public let languageMode: String
    public let inputKind: String, inputMode: String
    public let audioSeconds: Double?
    public let thermalState: String, memorySaving: Bool
    public var voiceModelID: String?
    public var translationModelID: String?
    public var recognitionModelID: String?
    public var processingMode: String?
    public var fallbackReason: String?
    public var preprocessingSeconds: Double?
    public var previewBlocks: Int?
    public var verificationSeconds: Double?
    public var reusedPreviewBlocks: Int?
    public var retranslatedParts: Int?
    public var peakFootprintBytes: UInt64?
    public var peakResidentBytes: UInt64?
    public var endThermalState: String?
    public var status = "running"
    public var totalSeconds = 0.0, ttsSeconds = 0.0, spokenSeconds = 0.0
    public var asrSeconds: Double?, mtSeconds: Double?, firstTokenSeconds: Double?, playbackScheduledSeconds: Double?
    public var asrLoadSeconds: Double?, mtLoadSeconds: Double?, ttsLoadSeconds: Double?
    public var speechQueueWaitSeconds = 0.0, removedSilenceSeconds = 0.0
    public var mtFragments = 0, ttsFragments = 0
    public init(source: SpeechLanguage?, inputKind: String, inputMode: String, audioSeconds: Double?, thermalState: String, memorySaving: Bool) {
        self.source = source; self.languageMode = source == nil ? "auto" : "manual"; self.inputKind = inputKind; self.inputMode = inputMode; self.audioSeconds = audioSeconds; self.thermalState = thermalState; self.memorySaving = memorySaving
    }
    public var lengthRange: String {
        guard let s = audioSeconds else { return "text" }
        return s <= 5 ? "0-5s" : s <= 15 ? "5-15s" : s <= 30 ? "15-30s" : s <= 60 ? "30-60s" : s <= 180 ? "60-180s" : s <= 300 ? "180-300s" : s <= 600 ? "300-600s" : s <= 1800 ? "600-1800s" : "1800s+"
    }
    public static func export(_ samples: [Self], device: String, osVersion: String) throws -> Data {
        struct Group: Codable { let direction: String, languageMode: String, inputKind: String, lengthRange: String, status: String; let processingMode: String?; let voiceModelID: String?; let translationModelID: String?; let memorySaving: Bool; let count: Int; let p50: Double?, p95: Double? }
        struct Report: Codable { let schemaVersion: Int, device: String, osVersion: String; let revisions: [String: String]; let samples: [PipelineBenchmark], groups: [Group] }
        let buckets = Dictionary(grouping: samples) { "\($0.source?.rawValue ?? "unknown")-\($0.target?.rawValue ?? "unknown")|\($0.languageMode)|\($0.inputKind)|\($0.lengthRange)|\($0.status)|\($0.voiceModelID ?? "unknown")|\($0.memorySaving)|\($0.translationModelID ?? "legacy-gemma")|\($0.processingMode ?? "after-stop")" }
        let groups = buckets.keys.sorted().map { key in
            let values = buckets[key]!; let first = values[0]
            return Group(direction: first.source.map { $0.rawValue + "-" + (first.target ?? $0.opposite).rawValue } ?? "unknown", languageMode: first.languageMode, inputKind: first.inputKind, lengthRange: first.lengthRange, status: first.status, processingMode: first.processingMode, voiceModelID: first.voiceModelID, translationModelID: first.translationModelID, memorySaving: first.memorySaving, count: values.count,
                p50: BenchmarkRecorder.percentile(values.map(\.totalSeconds), fraction: 0.5), p95: BenchmarkRecorder.percentile(values.map(\.totalSeconds), fraction: 0.95))
        }
        var revisions = ["whisper": "927cfce34f31707e17f2bff35c349632fb9e2c3a", "whisperModel": ModelDescriptor.revision,
            "llama": "d81235049384534c167caea52b85a694f6103d14", "translationModel.gemma4B": TranslationModel.gemma4B.revision, "translationModel.index9B": TranslationModel.index9B.revision,
            "sherpa": "11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf", "onnxruntime": "1.28.1", "voices": "ru_RU-denis-medium+ru_RU-irina-medium+en_US-ljspeech-high+en_US-lessac-medium"]
        for model in TranslationModel.allCases { revisions["translationModel." + model.rawValue] = model.revision }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Report(schemaVersion: 7, device: device, osVersion: osVersion, revisions: revisions, samples: samples, groups: groups))
    }
}
