// Compile with OfflineCore; inputs are original .build/vits-piper-*-preview.wav files.
// Never normalize an already processed preview again.
import Foundation
import AVFoundation
import OfflineCore
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    precondition(file.processingFormat.channelCount == 1)
    let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: input)
    let samples = Array(UnsafeBufferPointer(start: input.floatChannelData![0], count: Int(input.frameLength)))
    let pcm = SpeechLoudness.normalize(SpeechSilenceLimiter.compact(SpeechPCM(samples: samples, sampleRate: Int(file.processingFormat.sampleRate))))
    let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-preview", with: "")
    let destination = URL(fileURLWithPath: "assets/bundled/VoicePreviews/" + name + ".m4a")
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(name + ".new.m4a")
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(pcm.samples.count))!
    buffer.frameLength = buffer.frameCapacity
    pcm.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
    do {
        let output = try AVAudioFile(forWriting: temporary, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: pcm.sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000], commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: buffer)
    }
    if FileManager.default.fileExists(atPath: destination.path) {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    print(name, pcm.samples.count, "normalized samples")
}
