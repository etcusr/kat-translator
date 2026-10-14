import Foundation
import Darwin
import os
import OfflineCore

/// Opt-in device-test telemetry. No text/audio is recorded; normal launches create no file.
/// Called only on the speech backend's serial queue.
enum SpeechMemoryTrace {
    static func record(_ phase: String, model: String, seconds: Double? = nil, code: Int32? = nil) {
        guard ProcessInfo.processInfo.environment["OT_TTS_MEMORY_TRACE"] == "1" else { return }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        var row: [String: Any] = ["phase": phase, "model": model, "pid": ProcessInfo.processInfo.processIdentifier,
            "timestamp": Date().timeIntervalSince1970, "time": ISO8601DateFormatter().string(from: Date()),
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
        #if os(iOS)
        row["availableBytes"] = os_proc_available_memory()
        #endif
        if result == KERN_SUCCESS {
            row["footprintBytes"] = info.phys_footprint
            row["processLifetimePeakBytes"] = info.ledger_phys_footprint_peak
            row["residentBytes"] = info.resident_size
            row["residentPeakBytes"] = info.resident_size_peak
        }
        if let seconds { row["seconds"] = seconds }
        if let code { row["code"] = code }
        do {
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); data.append(10)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tts-memory-probe.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data); try file.synchronize()
        } catch { NSLog("Memory trace write failed: %@", error.localizedDescription) }
    }
}
