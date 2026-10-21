import AVFoundation
import Combine
import OfflineCore

private final class RecordingSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.audio-conversion")
    private let lock = NSLock()
    private var paused = false
    private var pending = 0
    private var tracedFirstBuffer = false
    private var failed = false
    private var buffer: BoundedRecordingBuffer
    private var conversionError: Error?
    private let normalizer = AudioNormalizer()
    private let detector: SpeechActivityDetector
    var onBoundary: (@Sendable (Int, Bool) -> Void)?
    private var offeredBoundary = 0
    let onFailure: @Sendable () -> Void
    let onLimit: @Sendable () -> Void
    init(detector: SpeechActivityDetector, maxSeconds: Int, onLimit: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable () -> Void) {
        self.detector = detector; buffer = BoundedRecordingBuffer(maxSeconds: maxSeconds)
        self.onLimit = onLimit; self.onFailure = onFailure
    }
    func setPaused(_ value: Bool) { lock.lock(); paused = value; lock.unlock() }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard !paused else { lock.unlock(); return }
        guard pending < 8, !failed else {
            let first = !failed; failed = true; lock.unlock()
            if first { onFailure() }; return
        }
        let traceFirst = RecordingStopTrace.enabled && !tracedFirstBuffer
        tracedFirstBuffer = true
        pending += 1; lock.unlock()
        if traceFirst {
            let time = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in RecordingStopTrace.mark("start.firstPCM", at: time) }
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            lock.lock(); pending -= 1; failed = true; lock.unlock(); onFailure(); return
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, target) {
            if let s = src.mData, let d = dst.mData { memcpy(d, s, Int(src.mDataByteSize)) }
        }
        queue.async {
            defer { self.lock.lock(); self.pending -= 1; self.lock.unlock() }
            do {
                let converted = try self.normalizer.convert(copy)
                let silence = self.detector.append(converted)
                let limit = self.buffer.append(converted)
                if let end = self.detector.latestBoundary, end > self.offeredBoundary {
                    self.offeredBoundary = end; self.onBoundary?(min(end, self.buffer.samples.count), self.detector.latestBoundaryEndsInSilence)
                }
                if silence || limit { self.onLimit() }
            } catch { self.conversionError = error; self.onFailure() }
        }
    }
    func snapshot(_ range: Range<Int>) async throws -> CapturedAudio {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard range.lowerBound >= 0, range.upperBound <= self.buffer.samples.count else { continuation.resume(throwing: CancellationError()); return }
                continuation.resume(returning: CapturedAudio(samples: Array(self.buffer.samples[range])))
            }
        }
    }
    func speechEnd() async -> Int { await withCheckedContinuation { c in queue.async { c.resume(returning: self.detector.lastSpeechEnd) } } }
    func finish() async throws -> CapturedAudio {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let tail = try self.normalizer.finish()
                    _ = self.buffer.append(tail)
                } catch { self.conversionError = error }
                self.lock.lock(); let failed = self.failed; self.lock.unlock()
                if let error = self.conversionError { continuation.resume(throwing: error) }
                else if failed {
                    continuation.resume(throwing: NSError(domain: "Audio", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: L10n.text("Телефон не успевает обработать запись. Попробуйте снова.")]))
                } else if !self.detector.heardSpeech { continuation.resume(throwing: PipelineError.noSpeech) }
                else { continuation.resume(returning: CapturedAudio(samples: self.buffer.samples)) }

            }
        }
    }
}

/// One exclusive off-main operation. No caller touches the engine until the
/// continuation returns, including cancellation/route-change cleanup.
private struct RecordingEngineStartup: @unchecked Sendable {
    let engine: AVAudioEngine
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try engine.start(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
            if RecordingStopTrace.enabled { Task { @MainActor in RecordingStopTrace.mark("start.mainResponsive") } }
        }
    }
}

@MainActor final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var starting = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var limitSeconds = RecordingPolicy.limitSeconds(minutes: RecordingPolicy.defaultMinutes)
    var onBoundary: ((Int, Bool) -> Void)?
    private(set) var finalSpeechEnd = 0
    var previewSnapshot: RecordingPreviewCoordinator.Snapshot? {
        guard let sink else { return nil }
        return { range in try await sink.snapshot(range) }
    }
    var onLimit: (() -> Void)?
    var onInterruption: ((String) -> Void)?
    private var engineStartInFlight = false
    private var engine: AVAudioEngine?
    #if os(iOS)
    private var inputQueue: AudioQueueCapture?
    #endif
    private var sink: RecordingSink?
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var clock: RecordingClock?
    private var deferredLimit = false
    #if os(iOS)
    private var activatedSession = false
    #endif
    init() {
        #if os(iOS)
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                // Activating our own audio category also posts route-change notifications.
                // Only a hardware-route loss/change or a new interruption invalidates capture.
                if name == AVAudioSession.routeChangeNotification {
                    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                    guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
                        || reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue else { return }
                } else {
                    let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                    guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
                }
                Task { @MainActor in
                    guard let self, self.isRecording || self.starting else { return }
                    self.cancel(); self.onInterruption?(L10n.text("Запись прервана. Нажмите кнопку, чтобы начать снова."))
                }
            })
        }
        #endif
    }
    func start(silenceSeconds: Double = SilenceMonitor.defaultTimeout, limitMinutes: Double = RecordingPolicy.defaultMinutes) async throws {
        try Task.checkCancellation()
        guard !isRecording, !starting else { return }
        RecordingStopTrace.mark("start.recorder")
        starting = true; generation += 1; let operation = generation
        defer { starting = false }
        #if os(macOS)
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        #else
        let permitted = await AVAudioApplication.requestRecordPermission()
        #endif
        RecordingStopTrace.mark("start.permissionReady")
        guard generation == operation, !Task.isCancelled else { throw CancellationError() }
        guard permitted else {
            throw NSError(domain: "Audio", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("Разрешите доступ к микрофону в настройках iPhone.")])
        }
        guard generation == operation, !Task.isCancelled else { throw CancellationError() }
        guard let vadURL = Bundle.main.url(forResource: "silero_vad", withExtension: "onnx") else { throw PipelineError.modelLoad }
        RecordingStopTrace.mark("start.vadBegin")
        let detector = try await Task.detached { try SpeechActivityDetector(modelURL: vadURL, silenceSeconds: silenceSeconds) }.value
        guard generation == operation, !Task.isCancelled else { throw CancellationError() }
        RecordingStopTrace.mark("start.vadReady")
        var started = false
        defer { if !started { cancel() } }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        RecordingStopTrace.mark("start.sessionBegin")
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        activatedSession = true
        RecordingStopTrace.mark("start.sessionReady")
        #endif
        #if os(iOS)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: session.sampleRate,
            channels: AVAudioChannelCount(session.inputNumberOfChannels), interleaved: true),
            format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.invalidFormat }
        #else
        let engine = AVAudioEngine()
        RecordingStopTrace.mark("start.engineCreated")
        let input = engine.inputNode
        RecordingStopTrace.mark("start.inputReady")
        let format = input.outputFormat(forBus: 0)
        RecordingStopTrace.mark("start.formatReady")
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.invalidFormat }
        #endif
        let limit = RecordingPolicy.limitSeconds(minutes: limitMinutes)
        limitSeconds = limit
        let sink = RecordingSink(detector: detector, maxSeconds: limit, onLimit: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == operation, self.isRecording else { return }
                if self.isPaused { self.deferredLimit = true } else { self.onLimit?() }
            }
        }) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == operation else { return }
                self.cancel(); self.onInterruption?(L10n.text("Ошибка обработки записи. Попробуйте снова."))
            }
        }
        sink.onBoundary = { [weak self] end, quiet in
            Task { @MainActor in
                guard let self, self.generation == operation, self.isRecording else { return }
                self.onBoundary?(end, quiet)
            }
        }
        finalSpeechEnd = 0
        #if os(iOS)
        self.sink = sink
        let capture = AudioQueueCapture(format: format, receive: { sink.append($0) }, failure: sink.onFailure)
        RecordingStopTrace.mark("start.enginePrepared")
        engineStartInFlight = true
        do { try await capture.start() }
        catch {
            engineStartInFlight = false; inputQueue = capture
            guard generation == operation, !Task.isCancelled else { throw CancellationError() }
            throw error
        }
        engineStartInFlight = false; inputQueue = capture
        guard generation == operation, !Task.isCancelled else { throw CancellationError() }
        #else
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in sink.append(buffer) }
        RecordingStopTrace.mark("start.tapReady")
        self.sink = sink
        engine.prepare()
        RecordingStopTrace.mark("start.enginePrepared")
        // start() can wait for the audio service for over a second. The engine is
        // owned by this operation until it completes; cancellation only latches
        // the generation and pauses the sink, never stopping a starting engine.
        engineStartInFlight = true
        let startup = RecordingEngineStartup(engine: engine)
        do {
            try await startup.start()
        } catch {
            engineStartInFlight = false; self.engine = engine
            guard generation == operation, !Task.isCancelled else { throw CancellationError() }
            throw error
        }
        engineStartInFlight = false; self.engine = engine
        guard generation == operation, !Task.isCancelled else { throw CancellationError() }
        #endif
        RecordingStopTrace.mark("start.engineReady")
        elapsed = 0; isPaused = false; deferredLimit = false; isRecording = true
        started = true
        clock = RecordingClock(start: ProcessInfo.processInfo.systemUptime)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isRecording, !Task.isCancelled else { return }
                guard !self.isPaused else { continue }
                self.elapsed = min(Double(limit), self.clock?.elapsed(at: ProcessInfo.processInfo.systemUptime) ?? 0)
                if self.elapsed >= Double(limit) { self.onLimit?(); return }
            }
        }
    }
    func togglePause() {
        guard isRecording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if isPaused {
            do {
                #if os(iOS)
                // Resume can deliver PCM before AudioQueueStart returns.
                sink?.setPaused(false)
                try inputQueue?.resume()
                #else
                try engine?.start()
                #endif
            } catch {
                cancel(); onInterruption?(L10n.text("Не удалось продолжить запись. Попробуйте снова.")); return
            }
            clock?.resume(at: now); isPaused = false; sink?.setPaused(false)
            if deferredLimit { deferredLimit = false; onLimit?() }
        } else {
            sink?.setPaused(true)
            #if os(iOS)
            inputQueue?.pause()
            #else
            engine?.pause()
            #endif
            clock?.pause(at: now)
            elapsed = min(Double(limitSeconds), clock?.elapsed(at: now) ?? elapsed)
            isPaused = true
        }
    }
    func stop() async throws -> CapturedAudio {
        guard isRecording, let sink else { throw CancellationError() }
        RecordingStopTrace.mark("recorder.stop.begin")
        stopEngine(); self.sink = nil
        RecordingStopTrace.mark("recorder.stop.engineDone")
        let audio = try await sink.finish()
        RecordingStopTrace.mark("recorder.stop.sinkDone")
        finalSpeechEnd = await sink.speechEnd()
        return audio
    }
    func cancel() {
        generation += 1; stopEngine(); sink = nil
    }
    private func stopEngine() {
        sink?.setPaused(true)
        timer?.cancel(); timer = nil
        #if os(iOS)
        inputQueue?.stop(); inputQueue = nil
        #else
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        #endif
        isRecording = false; isPaused = false; clock = nil; deferredLimit = false
        #if os(iOS)
        // Idle cleanup must not stop another player's process-wide audio session.
        // Track activation separately: setup can fail before engine is assigned.
        if activatedSession, !engineStartInFlight {
            activatedSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}

// Opt-in development fixture replay. Uses the same converter, VAD and bounded sink as capture.
// No user recordings are read; only the explicitly provided fixture file is replayed.
extension AudioRecorder {
    static func replayFixture(_ url: URL,
                              started: @MainActor (@escaping RecordingPreviewCoordinator.Snapshot) -> Void,
                              boundary: @escaping @MainActor (Int, Bool) -> Void) async throws -> (CapturedAudio, Int) {
        guard let vadURL = Bundle.main.url(forResource: "silero_vad", withExtension: "onnx") else { throw PipelineError.modelLoad }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let detector = try SpeechActivityDetector(modelURL: vadURL, silenceSeconds: 30)
        guard Double(file.length) / format.sampleRate <= 600 else { throw PipelineError.invalidAudio }
        let sink = RecordingSink(detector: detector, maxSeconds: 600, onLimit: {}, onFailure: {})
        sink.onBoundary = { end, quiet in Task { @MainActor in boundary(end, quiet) } }
        started { range in try await sink.snapshot(range) }
        let start = ProcessInfo.processInfo.systemUptime
        var sent: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(1024, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw PipelineError.invalidAudio }
            try file.read(into: buffer, frameCount: frames)
            sink.append(buffer); sent += AVAudioFramePosition(buffer.frameLength)
            let remaining = Double(sent) / format.sampleRate - (ProcessInfo.processInfo.systemUptime - start)
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
        let audio = try await sink.finish()
        return (audio, await sink.speechEnd())
    }
}
