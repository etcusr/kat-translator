// Run with swift ExportPCM.swift input.aiff output.f32; private outputs must stay outside Git.
import Foundation
import AVFoundation
import CryptoKit
let args = CommandLine.arguments
precondition(args.count == 3, "Provide input AIFF and output f32 paths")
let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
// This is the exact no-conversion fast path used by Kat's AudioNormalizer.
precondition(file.processingFormat == target, "Fixture must be mono Float32 processing format at 16 kHz")
var bytes = Data()
while file.framePosition < file.length {
    let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 1024)!
    try file.read(into: buffer, frameCount: min(1024, AVAudioFrameCount(file.length-file.framePosition)))
    bytes.append(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}
try bytes.write(to: URL(fileURLWithPath: args[2]), options: .atomic)
print("Samples:", bytes.count / 4, "SHA256:", SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
