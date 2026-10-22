import Foundation
import UIKit
import Darwin
import os

/// Kat Audit Lab only (copied in by prepare.py). Test speech is never played from the Mac and the Files
/// picker is not used: the host writes Documents/AudioTests/trigger.txt with a file name, and the lab imports
/// Documents/AudioTests/<name> through the ordinary audio-file path ("image:<name>": the camera's Gallery path). Memory is sampled every 0.5 s to
/// Documents/lab-memory.jsonl together with memory warnings.
@MainActor enum LabAudioTrigger {
    static func start(_ model: AppModel) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let trigger = documents.appendingPathComponent("AudioTests/trigger.txt")
        let log = documents.appendingPathComponent("lab-memory.jsonl")
        func write(_ row: [String: Any]) {
            var row = row; row["t"] = Date().timeIntervalSince1970
            guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
            data.append(10)
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: log) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            write(["event": "memoryWarning"])
        }
        Task { @MainActor in
            while true {
                var info = task_vm_info_data_t()
                var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                let capacity = Int(count)
                let ok = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: capacity) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
                } == KERN_SUCCESS
                write(["footprint": ok ? info.phys_footprint : 0, "peak": ok ? info.ledger_phys_footprint_peak : 0,
                       "available": os_proc_available_memory(), "busy": model.session.isBusy, "importing": model.importingAudio])
                if let name = try? String(contentsOf: trigger, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    try? FileManager.default.removeItem(at: trigger)
                    write(["event": "import", "file": name])
                    if name.hasPrefix("image:") { // camera picture, the same path as Gallery (camera must be open)
                        let url = documents.appendingPathComponent("AudioTests/" + name.dropFirst(6))
                        if let data = try? Data(contentsOf: url) { Task { await model.camera.importData(data) } }
                    } else {
                        Task { await model.importAudioFile(documents.appendingPathComponent("AudioTests/" + name)) }
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
