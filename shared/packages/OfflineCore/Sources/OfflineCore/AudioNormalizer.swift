import AVFoundation
public struct CapturedAudio: Sendable {
    public let samples: [Float]
    public var durationSeconds: Double { Double(samples.count) / 16000 }
    public init(samples: [Float]) { self.samples = samples }
}
public enum AudioError: LocalizedError {
    case invalidFormat, conversionFailed
    public var errorDescription: String? { L10n.text("Не удалось обработать формат записи микрофона.") }
}
public final class AudioNormalizer {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    public init() {}
    public func finish() throws -> [Float] {
        guard let converter else { return [] }
        defer { self.converter = nil; inputFormat = nil }
        var result: [Float] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 4096) else { throw AudioError.invalidFormat }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                state.pointee = .endOfStream; return nil
            }
            if let error { throw error }
            guard status != .error else { throw AudioError.conversionFailed }
            if let samples = output.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
            }
            if status == .endOfStream || output.frameLength == 0 { return result }
        }
    }
    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        guard buffer.format.sampleRate > 0, buffer.format.channelCount > 0 else { throw AudioError.invalidFormat }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        if buffer.format == target, let samples = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        }
        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: target)
            // Mix every input channel: interfaces and aggregate devices may carry the microphone on any channel.
            converter?.downmix = true
        }
        guard let converter else { throw AudioError.invalidFormat }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw AudioError.invalidFormat }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard !supplied else { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        if let error { throw error }
        guard status != .error, let samples = output.floatChannelData?[0] else { throw AudioError.conversionFailed }
        return Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
    }
}
