import Foundation
import OfflineCore
final class SpeechActivityDetector: @unchecked Sendable {
    private let vad: OpaquePointer
    private var pending: [Float] = []
    private var monitor: SilenceMonitor
    private var previewBoundary = RecordingPreviewBoundary()
    private(set) var latestBoundary: Int?
    var lastSpeechEnd: Int { previewBoundary.lastSpeechEnd }
    var heardSpeech: Bool { monitor.heardSpeech }
    init(modelURL: URL, silenceSeconds: Double) throws {
        monitor = SilenceMonitor(timeout: silenceSeconds)
        guard let vad = ot_vad_create(modelURL.path) else { throw PipelineError.modelLoad }
        self.vad = vad
    }
    // Called only from RecordingSink's serial conversion queue.
    func append(_ samples: [Float]) -> Bool {
        pending.append(contentsOf: samples)
        var stop = false; var offset = 0
        while pending.count - offset >= 512 {
            pending.withUnsafeBufferPointer { buffer in
                SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, buffer.baseAddress!.advanced(by: offset), 512)
            }
            let speech = SherpaOnnxVoiceActivityDetectorDetected(vad) != 0
            if let end = previewBoundary.observe(speech: speech, sampleCount: 512) { latestBoundary = end }
            if monitor.observe(speech: speech, seconds: 512.0 / 16000) { stop = true }
            while SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0 { SherpaOnnxVoiceActivityDetectorPop(vad) }
            offset += 512
        }
        if offset > 0 { pending.removeFirst(offset) }
        return stop
    }
    deinit { SherpaOnnxDestroyVoiceActivityDetector(vad) }
}
