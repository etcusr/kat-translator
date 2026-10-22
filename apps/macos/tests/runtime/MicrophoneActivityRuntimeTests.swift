import XCTest
import AVFoundation
import SwiftUI
import OfflineCore
@testable import Kat_translator

final class MicrophoneActivityRuntimeTests: XCTestCase {
    func testSinkMeterPauseFreshnessAndUnchangedPCM() async throws {
        let vad = try XCTUnwrap(Bundle.main.url(forResource: "silero_vad", withExtension: "onnx"))
        let detector = try SpeechActivityDetector(modelURL: vad, silenceSeconds: 30)
        let sink = RecordingSink(detector: detector, maxSeconds: 30, onLimit: {}, onFailure: { XCTFail("Capture failed") })
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        let angularFrequency = 2.0 * Double.pi * 440.0 / 16000.0
        let input: [Float] = (0..<1600).map { Float(sin(Double($0) * angularFrequency) * 0.1) }
        for i in input.indices { buffer.floatChannelData![0][i] = input[i] }
        let normalizer = AudioNormalizer()
        let expected = try normalizer.convert(buffer)
        sink.append(buffer)
        let captured = try await sink.snapshot(0..<expected.count) // serial queue barrier
        XCTAssertEqual(captured.samples, expected)
        XCTAssertGreaterThan(sink.microphoneActivity(at: ProcessInfo.processInfo.systemUptime).level, 0.3)
        XCTAssertEqual(sink.microphoneActivity(at: ProcessInfo.processInfo.systemUptime + 1), .quiet)
        sink.setPaused(true)
        sink.append(buffer)
        XCTAssertEqual(sink.microphoneActivity(at: ProcessInfo.processInfo.systemUptime), .quiet)
        let paused = try await sink.snapshot(0..<expected.count)
        XCTAssertEqual(paused.samples, expected)
        sink.setPaused(false)
        XCTAssertEqual(sink.microphoneActivity(at: ProcessInfo.processInfo.systemUptime), .quiet)
        sink.append(buffer)
        let resumed = try await sink.snapshot(0..<(expected.count * 2))
        XCTAssertEqual(resumed.samples, expected + expected)
        XCTAssertGreaterThan(sink.microphoneActivity(at: ProcessInfo.processInfo.systemUptime).level, 0.3)
    }

    @MainActor func testMeterStatesKeepGeometryAndRender() throws {
        let activity = MicrophoneActivityState()
        var reference: CGSize?
        for (name, value, paused, reduced) in [
            ("quiet", MicrophoneActivity.quiet, false, false),
            ("sound", MicrophoneActivity(samples: [0.15], speechDetected: false), false, false),
            ("speech", MicrophoneActivity(samples: [0.15], speechDetected: true), false, false),
            ("paused", MicrophoneActivity(samples: [0.15], speechDetected: true), true, false),
            ("reduced-motion", MicrophoneActivity(samples: [0.15], speechDetected: true), false, true)
        ] {
            activity.update(value)
            let renderer = ImageRenderer(content: ZStack {
                    MicrophoneActivityBarsDisplay(levels: (0..<25).map { value.level * (0.35 + 0.65 * abs(sin(Double($0) * 0.7))) }, paused: paused, reduceMotion: reduced, diameter: 100)
                    RecordButton(mode: .toggle, enabled: false, recording: true, starting: false, processing: false, paused: paused, diameter: 100, start: {}, stop: {})
                }.frame(width: 260, height: 140)
                .padding(16).background(.black))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            if let reference { XCTAssertEqual(image.size, reference) } else { reference = image.size }
            let attachment = XCTAttachment(image: image); attachment.name = "microphone-" + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let recorder = AudioRecorder()
        recorder.microphoneActivity.update(MicrophoneActivity(samples: [0.15], speechDetected: true))
        recorder.cancel()
        XCTAssertEqual(recorder.microphoneActivity.value, .quiet)
    }
}
