import Foundation
import AVFoundation

/// The current microphone recording is usable even when audio history is disabled.
@MainActor final class VoiceRecordingCache {
    private let root: URL
    private var generation = 0
    private(set) var url: URL?
    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("KatVoiceRecording").appendingPathComponent(UUID().uuidString)) {
        self.root = root
    }
    func replace(with audio: CapturedAudio) async throws {
        clear()
        let id = generation
        let destination = root.appendingPathComponent(UUID().uuidString + ".m4a")
        let work = Task.detached(priority: .userInitiated) {
            try Self.write(audio, to: destination)
        }
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard id == generation else { throw CancellationError() }
            url = destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    nonisolated private static func write(_ audio: CapturedAudio, to destination: URL) throws {
        guard !audio.samples.isEmpty, audio.samples.allSatisfy(\.isFinite) else { throw AudioError.invalidFormat }
        try Task.checkCancellation()
        let gain = SpeechLoudness.recordingGain(for: audio.samples, sampleRate: 16000)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000,
                                     AVNumberOfChannelsKey: 1]
        let writer = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        #endif
        // Bounded buffers avoid another complete copy of a long microphone recording.
        for start in stride(from: 0, to: audio.samples.count, by: 16000) {
            try Task.checkCancellation()
            let count = min(16000, audio.samples.count - start)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let samples = buffer.floatChannelData?[0] else { throw AudioError.invalidFormat }
            buffer.frameLength = AVAudioFrameCount(count)
            if let gain {
                for offset in 0..<count { samples[offset] = SpeechLoudness.recordingAdjusted(audio.samples[start + offset], gain: gain) }
            } else {
                audio.samples.withUnsafeBufferPointer { samples.update(from: $0.baseAddress! + start, count: count) }
            }
            try writer.write(from: buffer)
        }
        // AVAudioFile finalizes the AAC container when this scope returns.
    }
    func copy(into directory: URL) throws -> URL? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let copy = directory.appendingPathComponent("Kat-original-" + formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8) + ".m4a")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
    func clear() {
        generation += 1; url = nil
        try? FileManager.default.removeItem(at: root)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
