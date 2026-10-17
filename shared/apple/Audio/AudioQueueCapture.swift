import AVFoundation
import OfflineCore

/// Input-only PCM capture. Startup owns the queue until it returns; stop/pause
/// must not overlap it. AudioRecorder enforces this with its startup generation.
final class AudioQueueCapture: @unchecked Sendable {
    private let format: AVAudioFormat
    private let receive: @Sendable (AVAudioPCMBuffer) -> Void
    private let failure: @Sendable () -> Void
    private var queue: AudioQueueRef?
    private let lock = NSLock()
    private var stopped = false
    private var receivedFirstBuffer = false
    private let firstBuffer = DispatchSemaphore(value: 0)

    init(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
         failure: @escaping @Sendable () -> Void) {
        self.format = format; self.receive = receive; self.failure = failure
    }
    static func copyPCM(_ data: UnsafeRawPointer, byteCount: Int, capacity: Int,
                        format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard format.commonFormat == .pcmFormatFloat32, format.isInterleaved,
              bytesPerFrame > 0, byteCount > 0, byteCount <= capacity,
              byteCount % bytesPerFrame == 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(byteCount / bytesPerFrame)),
              let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else { throw AudioError.invalidFormat }
        buffer.frameLength = buffer.frameCapacity
        memcpy(destination, data, byteCount)
        return buffer
    }
    private func received(_ buffer: AudioQueueBufferRef, queue: AudioQueueRef) {
        lock.lock(); let active = !stopped; lock.unlock()
        guard active else { return }
        do {
            let pcm = try Self.copyPCM(buffer.pointee.mAudioData,
                byteCount: Int(buffer.pointee.mAudioDataByteSize),
                capacity: Int(buffer.pointee.mAudioDataBytesCapacity), format: format)
            receive(pcm)
            lock.lock()
            if !receivedFirstBuffer { receivedFirstBuffer = true; firstBuffer.signal() }
            let status = stopped ? noErr : AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            lock.unlock()
            if status != noErr { failure() }
        } catch { failure() }
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try self.startSynchronously(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
            if RecordingStopTrace.enabled { Task { @MainActor in RecordingStopTrace.mark("start.mainResponsive") } }
        }
    }
    private func startSynchronously() throws {
        var description = format.streamDescription.pointee
        var created: AudioQueueRef?
        try check(AudioQueueNewInput(&description, { context, queue, buffer, _, _, _ in
            Unmanaged<AudioQueueCapture>.fromOpaque(context!).takeUnretainedValue().received(buffer, queue: queue)
        }, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &created))
        guard let created else { throw AudioError.invalidFormat }
        queue = created
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            try check(AudioQueueAllocateBuffer(created, 2048 * description.mBytesPerFrame, &buffer))
            guard let buffer else { throw AudioError.invalidFormat }
            try check(AudioQueueEnqueueBuffer(created, buffer, 0, nil))
        }
        try check(AudioQueueStart(created, nil))
        // AudioQueueStart may return before audio arrives. Do not announce
        // recording until the first buffer has been copied into the sink.
        guard firstBuffer.wait(timeout: .now() + 3) == .success else { throw AudioError.conversionFailed }
    }
    func pause() { if let queue { AudioQueuePause(queue) } }
    func resume() throws { if let queue { try check(AudioQueueStart(queue, nil)) } }
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            self.queue = nil
        }
    }
    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    deinit { stop() }
}
