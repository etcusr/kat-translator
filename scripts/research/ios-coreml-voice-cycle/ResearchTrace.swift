import Foundation
import UIKit
import AVFoundation
import Darwin
import os
import CryptoKit
import OfflineCore

/// Included only in a disposable source snapshot, never in Kat's shipping targets.
enum ResearchTrace {
    static let lock = NSLock()
    static var timer: DispatchSourceTimer?
    static var file: FileHandle?
    static func configure() {
        precondition(Bundle.main.bundleIdentifier == "app.kattranslator.voicelab")
        let defaults = UserDefaults.standard
        let speak = ProcessInfo.processInfo.environment["LAB_SPEAK"] == "1"
        // Typed values affect only the independent lab's preferences.
        let settings: [String: Any] = [
            "appInterfaceLanguage": "ru", "languageSetupCompleted": true,
            "selectedTranslationModel": "index-translate-9b-q4km",
            "translationAuto": false, "recognitionPreference": "whisper",
            "translationSource": "ru", "translationTarget": "en", "automaticLanguage": false,
            "automaticModelLoad": true, "automaticSpeechVoice": speak,
            "memorySaving": false, "recordingMode": "toggle",
            "recordingSilenceSeconds": 30.0, "recordingPreprocessing": true,
            "recordingPreviewVerification": true, "whisperDateTimeRepair": false,
            "historyRecordText": false, "historyRecordAudio": false,
            "voice.en": "vits-piper-en_US-lessac-medium",
            "voice.ru": "vits-piper-ru_RU-irina-medium"
        ]
        for (key, value) in settings { defaults.set(value, forKey: key) }
        if defaults.object(forKey: "showTechnicalInfo") == nil {
            defaults.set(true, forKey: "showTechnicalInfo")
        }
        defaults.removeObject(forKey: "unfinishedAutomaticModelLoad")
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
        setenv("OT_MT_MEMORY_TRACE", "1", 1)
        setenv("OT_TTS_MEMORY_TRACE", "1", 1)
        let environment = ProcessInfo.processInfo.environment
        let variant = environment["LAB_VARIANT"] ?? (environment["LAB_BASELINE"] == "1" ? "f16" : "coreml-q8")
        precondition(["f16", "q8", "coreml-q8"].contains(variant))
        let baseline = variant == "f16"
        setenv("LAB_BASELINE", baseline ? "1" : "0", 1)
        setenv("BENCH_COREML_UNITS", variant == "coreml-q8" ? "all" : "off", 1)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        setenv("BENCH_COREML_ENCODER", documents.appendingPathComponent("Research/turbo-encoder.mlmodelc").path, 1)
        let url = documents.appendingPathComponent("voice-lab.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        file = try? FileHandle(forWritingTo: url)
        record("launch", ["baseline": baseline, "variant": variant, "memorySaving": false, "automaticSpeech": speak])
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "kat.lab.memory"))
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { record("sample") }; t.resume(); timer = t
    }
    static func decodedFile(_ audio: CapturedAudio) {
        let digest = audio.samples.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        record("file.decoded", ["samples": audio.samples.count, "seconds": audio.durationSeconds,
                               "pcmSHA256": digest.map { String(format: "%02x", $0) }.joined()])
    }
    static func record(_ phase: String, _ extra: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var row = extra
        row["phase"] = phase
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        row["timestamp"] = Date().timeIntervalSince1970
        row["thermal"] = ProcessInfo.processInfo.thermalState.rawValue
        row["availableBytes"] = os_proc_available_memory()
        if result == KERN_SUCCESS {
            row["footprintBytes"] = info.phys_footprint
            row["lifetimePeakBytes"] = info.ledger_phys_footprint_peak
            row["residentBytes"] = info.resident_size
        }
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10); try? file?.write(contentsOf: data)
        if phase != "sample" { try? file?.synchronize() }
    }
    @MainActor static func finished(_ model: AppModel) {
        var row: [String: Any] = [
            "ready": model.session.isReady, "voiceReady": model.isVoiceReady,
            "source": model.session.voiceFields.sourceText,
            "translation": model.session.voiceFields.translatedText,
            "message": model.message ?? "", "error": model.session.error ?? ""
        ]
        if let metric = model.session.samples.last,
           let encoded = try? JSONEncoder().encode(metric),
           let value = try? JSONSerialization.jsonObject(with: encoded) { row["metric"] = value }
        record("cycle.finished", row)
    }
}
