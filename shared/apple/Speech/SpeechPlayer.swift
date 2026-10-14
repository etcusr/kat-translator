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
    private var observers: [NSObjectProtocol] = []
    #if os(iOS)
    private var activatedSession = false
    #endif
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
            activatedSession = true
            #endif
            let engine = AVAudioEngine(); let node = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch(); timePitch.rate = rate
            self.engine = engine; self.node = node; self.timePitch = timePitch
            engine.attach(node); engine.attach(timePitch)
            engine.connect(node, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            observeInterruptions(of: engine)
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
    private func observeInterruptions(of engine: AVAudioEngine) {
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: nil) { [weak self, weak engine] _ in
                // The notification may arrive on the engine's internal queue.
                // Tear down later on MainActor, never inside that callback.
                Task { @MainActor in
                    guard let self, let engine, self.engine === engine else { return }
                    self.stop(throwing: PipelineError.invalidAudio)
                }
            })
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: nil) { [weak self, weak engine] notification in
                let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in
                    guard let self, let engine, self.engine === engine else { return }
                    self.stop(throwing: PipelineError.invalidAudio)
                }
            })
        #endif
    }
    func stop() { stop(throwing: CancellationError()) }
    private func stop(throwing error: Error) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        generation += 1
        let waiting = continuation; continuation = nil
        node?.stop(); engine?.stop(); node = nil; timePitch = nil; engine = nil; paused = false
        waiting?.resume(throwing: error)
        #if os(iOS)
        if activatedSession {
            activatedSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}
