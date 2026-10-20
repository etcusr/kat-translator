import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import Darwin

@objc public final class MLXRunner: NSObject {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let code = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return code == KERN_SUCCESS ? info.phys_footprint : 0
    }
    @objc public static func run(directory: String, run: String) {
        Task {
            let root = URL(fileURLWithPath: directory)
            let output = root.appendingPathComponent(run + ".json")
            var report: [String: Any] = ["backend": "mlx-audio-swift", "rows": [[String: Any]]()]
            report["fp16Activations"] = ProcessInfo.processInfo.environment["BENCH_MLX_FP16"] == "1"
            func save() {
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: output, options: .atomic)
                }
            }
            do {
                let start = ProcessInfo.processInfo.systemUptime
                let model = try await WhisperModel.fromDirectory(root.appendingPathComponent("mlx-f16"))
                eval(model)
                report["loadSeconds"] = ProcessInfo.processInfo.systemUptime - start
                report["os"] = ProcessInfo.processInfo.operatingSystemVersionString
                let items = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [[String: Any]]
                var rows = [[String: Any]]()
                for pass in 0...3 {
                    for item in pass % 2 == 0 ? items : Array(items.reversed()) {
                        let pcm = try Data(contentsOf: root.appendingPathComponent(item["path"] as! String))
                        let samples = pcm.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                        let audio = MLXArray(samples); eval(audio)
                        let params = STTGenerateParameters(maxTokens: 432, temperature: 0,
                            topP: 1, language: item["language"] as? String,
                            chunkDuration: 30, minChunkDuration: 0.1)
                        let thermal = ProcessInfo.processInfo.thermalState.rawValue
                        let started = ProcessInfo.processInfo.systemUptime
                        let result = model.generate(audio: audio, generationParameters: params)
                        let elapsed = ProcessInfo.processInfo.systemUptime - started
                        rows.append(["id": item["id"]!, "pass": pass, "warmup": pass == 0,
                            "seconds": elapsed, "audioSeconds": Double(samples.count) / 16000,
                            "text": result.text, "mlxPeak": Memory.peakMemory,
                            "memory": ["footprint": footprint()],
                            "thermalBefore": thermal, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
                        report["rows"] = rows; save()
                        print("MLX_BENCH \(item["id"]!) \(pass) \(elapsed)")
                    }
                }
                report["completed"] = true; save(); print("MLX_BENCH DONE")
            } catch {
                report["error"] = String(describing: error); save(); print("MLX_BENCH ERROR \(error)")
            }
        }
    }
}
