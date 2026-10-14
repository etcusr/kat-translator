import Foundation
import Metal

/// First-run device check, 3–5 s and no downloads. Index decoding streams every weight once per
/// token, so sustained memory read bandwidth (CPU, and the GPU through Metal) predicts tokens/s.
/// The mobile thermal margin mirrors Android; the Mac result is used without it.
struct DeviceProbeResult: Codable, Equatable, Sendable {
    var cpuGbps: Double
    var gpuGbps: Double
    var estimate9B: Double
    var strong: Bool
}

enum DeviceProbe {
    static let index9BGigabytes = 5.78
    #if os(iOS)
    static let thermalMargin = 0.7
    #else
    static let thermalMargin = 1.0
    #endif
    /// Calibrated with llama.cpp Metal Index 9B decoding on Mac M3 Pro (23 tokens/s).
    static let gpuEfficiency = 1.0
    static let cpuEfficiency = 0.8
    /// iPhone decodes 9B with MTP, which the bandwidth estimate leaves out; the user chose a lower
    /// bar so iPhone 17 Pro (7.0 tokens/s with the margin) counts as strong.
    #if os(iOS)
    static let strongTokensPerSecond = 6.0
    #else
    static let strongTokensPerSecond = 8.0
    #endif
    static let strongMemoryBytes: UInt64 = 11_500_000_000
    private static let key = "deviceProbeResult"

    static var saved: DeviceProbeResult? {
        // The class is re-derived so a threshold change applies to results saved by older builds.
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(DeviceProbeResult.self, from: $0) }
            .map { var result = $0; result.strong = isStrong(result.estimate9B); return result }
    }

    static func isStrong(_ estimate9B: Double) -> Bool {
        estimate9B >= strongTokensPerSecond && ProcessInfo.processInfo.physicalMemory >= strongMemoryBytes
    }

    static func run() async -> DeviceProbeResult {
        await Task.detached(priority: .userInitiated) {
            let cpu = kat_apple_read_bandwidth_gbps(4, 32 << 20, 1.5)
            let gpu = metalReadBandwidth(seconds: 2)
            let best = max(gpu > 0 ? gpuEfficiency * gpu : 0, cpu > 0 ? cpuEfficiency * cpu : 0)
            let estimate = thermalMargin * best / index9BGigabytes
            let result = DeviceProbeResult(cpuGbps: cpu, gpuGbps: gpu, estimate9B: estimate,
                strong: isStrong(estimate))
            if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: key) }
            return result
        }.value
    }

    /// Reads a 128 MB private buffer repeatedly with a simple compute kernel; GPU time is taken
    /// from command buffer timestamps, so CPU scheduling does not count.
    static func metalReadBandwidth(seconds: Double) -> Double {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return -1 }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void readsum(device const float4 *src [[buffer(0)]], device float *out [[buffer(1)]],
                            constant uint &count [[buffer(2)]], uint gid [[thread_position_in_grid]],
                            uint grid [[threads_per_grid]]) {
            float4 acc = 0;
            for (uint i = gid; i < count; i += grid) acc += src[i];
            out[gid] = acc.x + acc.y + acc.z + acc.w;
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "readsum"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return -1 }
        let bytes = 128 << 20, threads = 65_536
        guard let input = device.makeBuffer(length: bytes, options: .storageModePrivate),
              let output = device.makeBuffer(length: threads * 4, options: .storageModePrivate) else { return -1 }
        var count = UInt32(bytes / 16)
        func pass(_ repeats: Int) -> Double {
            guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else { return -1 }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(input, offset: 0, index: 0); encoder.setBuffer(output, offset: 0, index: 1)
            encoder.setBytes(&count, length: 4, index: 2)
            for _ in 0..<repeats {
                encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
            }
            encoder.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
            return buffer.gpuEndTime - buffer.gpuStartTime
        }
        _ = pass(1) // warm-up: page residency and pipeline
        var total = 0.0, read = 0.0
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let elapsed = pass(8)
            guard elapsed > 0 else { return -1 }
            total += elapsed; read += Double(bytes * 8)
        }
        return total > 0 ? read / total / 1e9 : -1
    }
}
