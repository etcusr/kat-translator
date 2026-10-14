import AVFoundation
import OfflineCore
@MainActor final class SpeechPlayer: SpeechPlayback {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var timePitch: AVAudioUnitTimePitch?
    private var paused = false
    private var rate: Float = 1
    private var continuation: CheckedContinuation<Void, Error>?
    private var generation = 0
    func play(_ pcm: SpeechPCM) async throws {
        try Task.checkCancellation()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(pcm.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.samples.count)),
              let samples = buffer.floatChannelData?[0] else { throw PipelineError.invalidAudio }
        buffer.frameLength = buffer.frameCapacity
        pcm.samples.withUnsafeBufferPointer { samples.update(from: $0.baseAddress!, count: $0.count) }
        try prepareEngine(format: format)
        try await schedule { node, id in
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finished(id) }
            }
        }
    }
    func play(file url: URL) async throws {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw PipelineError.invalidAudio }
        try prepareEngine(format: file.processingFormat)
        // Stream the complete M4A through the same node: pause, stop and speed remain identical.
        try await schedule { node, id in
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finished(id) }
            }
        }
    }
    private func prepareEngine(format: AVAudioFormat) throws {
        if engine == nil {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default); try session.setActive(true)
            #endif
            let engine = AVAudioEngine(); let node = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch(); timePitch.rate = rate
            self.engine = engine; self.node = node; self.timePitch = timePitch
            engine.attach(node); engine.attach(timePitch)
            engine.connect(node, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            do { try engine.start() } catch { stop(); throw error }
        }
    }
    private func schedule(_ enqueue: (AVAudioPlayerNode, Int) -> Void) async throws {
        guard let node else { throw PipelineError.invalidAudio }
        generation += 1; let id = generation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                enqueue(node, id)
                // A pause also applies if pressed during synthesis or between fragments.
                if !paused { node.play() }
            }
        } onCancel: { Task { @MainActor [weak self] in if self?.generation == id { self?.stop() } } }
    }
    private func finished(_ id: Int) {
        guard generation == id else { return }
        let waiting = continuation; continuation = nil
        waiting?.resume()
    }
    func pause() { paused = true; node?.pause() }
    func resume() { paused = false; if continuation != nil { node?.play() } }
    func setRate(_ rate: Float) { self.rate = rate; timePitch?.rate = rate }
    func stop() {
        generation += 1
        let waiting = continuation; continuation = nil
        node?.stop(); engine?.stop(); node = nil; timePitch = nil; engine = nil; paused = false
        waiting?.resume(throwing: CancellationError())
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
