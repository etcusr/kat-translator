import XCTest
import SwiftUI
import AVFoundation
import OfflineCore
#if os(macOS)
import AppKit
@testable import Kat_translator
#else
import UIKit
@testable import OfflineTranslator
#endif

/// Silent fixtures exercise the real AAC encoder, player and shared Voice UI on each device.
/// Never records the microphone, loads model weights or writes the user's history.
final class VoiceOriginalIntegrationTests: XCTestCase {
    @MainActor func testQuietOriginalFileIsAmplifiedOnDevice() async throws {
        let pipeline = ConversationPipeline(asr: OriginalTestASR(), translator: OriginalTestMT(),
            speech: OriginalTestSpeech(), player: SpeechPlayer())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceLevelTest-" + UUID().uuidString)
        defer { pipeline.clearTemporarySpeech(); try? FileManager.default.removeItem(at: directory) }
        await pipeline.prepare(PipelineFiles(asr: directory, translation: directory, voices: [:], translationModel: .index9B), memorySaving: false)
        var samples = (0..<32000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16000)) * 0.025 }
        samples[16000] = 0.99; samples[16001] = -0.99
        let audio = CapturedAudio(samples: samples)
        await pipeline.runRecording(audio: audio, speechEnd: 32000, source: .russian, target: .english,
            speakResult: false, inputMode: "fixture", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: false, fallbackReason: nil)
        let url = try XCTUnwrap(pipeline.copyOriginalRecording(into: directory))
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let decoded = Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
        let quiet = decoded[2000..<14000]
        let rms = sqrt(quiet.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(quiet.count))
        XCTAssertGreaterThan(rms, 0.06); XCTAssertLessThan(rms, 0.09)
        XCTAssertLessThan(decoded.map(abs).max()!, 1)
        XCTAssertEqual(audio.samples, samples)
        XCTAssertEqual(Double(buffer.frameLength) / file.processingFormat.sampleRate, 2, accuracy: 0.1)
        print("ORIGINAL_AUDIO_LEVEL", rms, "peak", decoded.map(abs).max()!)
        await pipeline.unload()
    }
    @MainActor func testOriginalRecordingPlaybackSharingAndLayout() async throws {
        let pipeline = ConversationPipeline(asr: OriginalTestASR(), translator: OriginalTestMT(),
            speech: OriginalTestSpeech(), player: SpeechPlayer())
        let model = AppModel(session: pipeline)
        await model.packages.restore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceOriginalTest-" + UUID().uuidString)
        defer { pipeline.clearTemporarySpeech(); try? FileManager.default.removeItem(at: directory) }
        await pipeline.prepare(PipelineFiles(asr: directory, translation: directory, voices: [.english: directory], translationModel: .index9B), memorySaving: false)
        let audio = CapturedAudio(samples: Array(repeating: 0, count: 16000))
        await pipeline.runRecording(audio: audio, speechEnd: 16000, source: .russian, target: .english,
            speakResult: true, inputMode: "fixture", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: false, fallbackReason: nil)
        XCTAssertNil(pipeline.voiceFields.error); XCTAssertNil(pipeline.voiceFields.archiveWarning)
        XCTAssertTrue(pipeline.hasOriginalRecording)
        XCTAssertNil(pipeline.voiceFields.lastHistoryID)
        XCTAssertTrue(pipeline.hasVoiceTranslationSpeech)
        let translationFile = try XCTUnwrap(pipeline.copyVoiceTranslationSpeech(into: directory.appendingPathComponent("translation")))
        XCTAssertGreaterThan(try AVAudioFile(forReading: translationFile).length, 0)
        let file = try XCTUnwrap(pipeline.copyOriginalRecording(into: directory))
        let decoded = try AVAudioFile(forReading: file)
        XCTAssertEqual(Double(decoded.length) / decoded.processingFormat.sampleRate, 1, accuracy: 0.1)
        await pipeline.playOriginalRecording()
        XCTAssertNil(pipeline.voiceFields.error); XCTAssertFalse(pipeline.isPlayingOriginalRecording)
        XCTAssertEqual(pipeline.voiceFields.sourceText, "Ваш номер готов. Заселение в одиннадцать тридцать.")
        #if os(macOS)
        let host = NSHostingView(rootView: ConversationView(model: model).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        #else
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: ConversationView(model: model).preferredColorScheme(.dark))
        let window = UIWindow(windowScene: scene); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        #endif
        attachment.name = "voice-original-audio-controls"; attachment.lifetime = .keepAlways; add(attachment)
        pipeline.clearFields(in: .voice)
        XCTAssertFalse(pipeline.hasOriginalRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "A sharing copy must survive clearing the original")
        await model.unload()
    }
}
private actor OriginalTestASR: ASRBackend {
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        ASRResult(text: "Ваш номер готов. Заселение в одиннадцать тридцать.", language: .russian, processingSeconds: 0.1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor OriginalTestMT: TranslationBackend {
    func load(modelURL: URL) async throws {}
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        TranslationResult(text: "Your room is ready. Check in at eleven thirty.", firstTokenSeconds: 0.1, processingSeconds: 0.2, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor OriginalTestSpeech: SpeechSynthesisBackend {
    func load(directory: URL, language: SpeechLanguage) async throws {}
    func synthesize(text: String) async throws -> SpeechPCM { SpeechPCM(samples: Array(repeating: 0, count: 22050), sampleRate: 22050) }
    nonisolated func cancel() {}
    func unload() async {}
}
