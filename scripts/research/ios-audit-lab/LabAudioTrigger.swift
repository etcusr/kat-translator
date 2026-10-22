import Foundation
import UIKit
import AVFoundation
import Darwin
import os

/// Kat Audit Lab only (copied in by prepare.py). Test speech is never played from the Mac and the Files
/// picker is not used: the host writes Documents/AudioTests/trigger.txt and the lab acts on it:
/// - "<name>": import Documents/AudioTests/<name> through the ordinary audio-file path;
/// - "image:<name>": the camera's former in-memory Gallery path; "imagefile:<name>": the file path (camera open);
/// - "rec:<name>": start recording and play <name> without stopping (background/interruption checks);
/// - "tail:<name>:<ms>[:<AVAudioSession mode>]": record from the microphone while the iPhone speaker plays <name>, and stop the
///   recording <ms> after playback ends (recording-tail check, audit O14).
/// Memory is sampled every 0.5 s to Documents/lab-memory.jsonl together with memory warnings and events.
/// Counts CameraView body evaluations; prepare.py inserts `let _ = LabRenderCounter.tick()` (audit 22.10, iOS C6).
@MainActor enum LabRenderCounter {
    static var count = 0
    static func tick() -> Int { count += 1; return count }
}

@MainActor enum LabAudioTrigger {
    private static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private static func write(_ row: [String: Any]) {
        let log = documents.appendingPathComponent("lab-memory.jsonl")
        var row = row; row["t"] = Date().timeIntervalSince1970
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: log) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close() }
    }
    static func start(_ model: AppModel) {
        let trigger = documents.appendingPathComponent("AudioTests/trigger.txt")
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in write(["event": "memoryWarning"]) }
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
                       "available": os_proc_available_memory(), "busy": model.session.isBusy, "importing": model.importingAudio,
                       "cameraRenders": LabRenderCounter.count])
                if let name = try? String(contentsOf: trigger, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    try? FileManager.default.removeItem(at: trigger)
                    write(["event": "import", "file": name])
                    let parts = name.split(separator: ":").map(String.init)
                    if parts.first == "image", parts.count == 2 {
                        if let data = try? Data(contentsOf: documents.appendingPathComponent("AudioTests/" + parts[1])) {
                            Task { await model.camera.importData(data) }
                        }
                    } else if parts.first == "imagefile", parts.count == 2 { // camera, Photos file path (C5); importFile deletes its input
                        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + parts[1])
                        if (try? FileManager.default.copyItem(at: documents.appendingPathComponent("AudioTests/" + parts[1]), to: copy)) != nil {
                            Task { await model.camera.importFile(copy) }
                        }
                    } else if parts.first == "play", parts.count == 2 { // playback alone, no recording
                        Task { await play(parts[1]) }
                    } else if parts.first == "rec", parts.count == 2 { // start recording and play <name>; no Stop (I2/I4)
                        Task { await record(model, file: parts[1]) }
                    } else if parts.first == "tail", parts.count >= 3 {
                        Task { await tail(model, file: parts[1], delay: Double(parts[2]) ?? 0, mode: parts.count > 3 ? parts[3] : "") }
                    } else {
                        Task { await model.importAudioFile(documents.appendingPathComponent("AudioTests/" + name)) }
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    private static var lastPlayer: AVAudioPlayer?
    private static func play(_ file: String) async {
        let audio = AVAudioSession.sharedInstance()
        do { try audio.setCategory(.playback, mode: .default); try audio.setActive(true) }
        catch { write(["event": "play.error", "reason": error.localizedDescription]); return }
        guard let player = try? AVAudioPlayer(contentsOf: documents.appendingPathComponent("AudioTests/" + file)) else { return }
        lastPlayer = player; player.volume = 1
        let started = player.play()
        write(["event": "play", "started": started, "outputVolume": audio.outputVolume,
               "route": audio.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")])
    }
    private static func record(_ model: AppModel, file: String) async {
        await model.beginRecording()
        for _ in 0..<100 where !model.recorder.isRecording { try? await Task.sleep(nanoseconds: 50_000_000) }
        guard model.recorder.isRecording else { write(["event": "rec.error", "reason": "not recording"]); return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let audio = AVAudioSession.sharedInstance()
        try? audio.setMode(.videoRecording); try? audio.overrideOutputAudioPort(.speaker)
        guard let player = try? AVAudioPlayer(contentsOf: documents.appendingPathComponent("AudioTests/" + file)) else { return }
        lastPlayer = player; player.play()
        write(["event": "rec.play", "file": file])
    }
    private static func tail(_ model: AppModel, file: String, delay: Double, mode: String) async {
        await model.beginRecording()
        for _ in 0..<100 where !model.recorder.isRecording { try? await Task.sleep(nanoseconds: 50_000_000) }
        guard model.recorder.isRecording else { write(["event": "tail.error", "reason": "not recording"]); return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let player = try? AVAudioPlayer(contentsOf: documents.appendingPathComponent("AudioTests/" + file)) else {
            write(["event": "tail.error", "reason": "player"]); return
        }
        // The recorder's .measurement mode can route output to the receiver; the check needs the loudspeaker.
        let audio = AVAudioSession.sharedInstance()
        // During recording (.measurement) the lab's playback was inaudible; switch only the mode for the playback.
        if !mode.isEmpty { do { try audio.setMode(AVAudioSession.Mode(rawValue: mode)) } catch { write(["event": "tail.modeError", "reason": error.localizedDescription]) } }
        try? audio.overrideOutputAudioPort(.speaker)
        player.volume = 1
        // Diagnostic copy of what the microphone hears during playback (analysed on the host, never played).
        let capture = try? AVAudioRecorder(url: documents.appendingPathComponent("tail-capture.wav"),
            settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
        capture?.record()
        player.play()
        write(["event": "tail.play", "file": file, "duration": player.duration, "outputVolume": audio.outputVolume,
               "route": audio.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ","), "category": audio.category.rawValue, "mode": audio.mode.rawValue])
        while player.isPlaying { try? await Task.sleep(nanoseconds: 5_000_000) }
        write(["event": "tail.playEnd"])
        capture?.stop()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
        await model.finishRecording()
        write(["event": "tail.stop", "delayMs": delay, "mode": mode])
    }
}
