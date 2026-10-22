import Foundation
import WhisperKit
import AVFoundation
import CoreML

/// Thread-safe in-memory PCM adapter; uses upstream energy calculation, no microphone.
final class ReplayAudio: AudioProcessing, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let base = AudioProcessor()
    private func access<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    var audioSamples: ContiguousArray<Float> { access { base.audioSamples } }
    var relativeEnergy: [Float] { access { base.relativeEnergy } }
    var relativeEnergyWindow: Int { get { access { base.relativeEnergyWindow } } set { access { base.relativeEnergyWindow = newValue } } }
    func append(_ samples: [Float]) { access { base.processBuffer(samples) } }
    func purgeAudioSamples(keepingLast keep: Int) { access { base.purgeAudioSamples(keepingLast: keep) } }
    func startRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws { access { base.audioBufferCallback = callback } }
    func pauseRecording() {}
    func stopRecording() { access { base.audioBufferCallback = nil } }
    func resumeRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws { try startRecordingLive(inputDeviceID: inputDeviceID, callback: callback) }
    func padOrTrim(fromArray a: [Float], startAt s: Int, toLength n: Int) -> (any AudioProcessorOutputType)? { base.padOrTrim(fromArray: a, startAt: s, toLength: n) }
    static func padOrTrimAudio(fromArray a: [Float], startAt s: Int, toLength n: Int, saveSegment: Bool) -> MLMultiArray? { AudioProcessor.padOrTrimAudio(fromArray: a, startAt: s, toLength: n, saveSegment: saveSegment) }
    static func loadAudio(fromPath p: String, channelMode: ChannelMode, startTime: Double?, endTime: Double?, maxReadFrameSize: AVAudioFrameCount?) throws -> AVAudioPCMBuffer { try AudioProcessor.loadAudio(fromPath: p, channelMode: channelMode, startTime: startTime, endTime: endTime, maxReadFrameSize: maxReadFrameSize) }
    static func loadAudio(at paths: [String], channelMode: ChannelMode) async -> [Result<[Float], Error>] { await AudioProcessor.loadAudio(at: paths, channelMode: channelMode) }
}
