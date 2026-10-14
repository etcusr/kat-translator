import XCTest
import AVFoundation
import CryptoKit
import UIKit
import OfflineCore
@testable import OfflineTranslator

/// Opt-in physical iPhone tests. Production ASR/MT/TTS, synthetic bundled previews,
/// No history archive; preferences and temporary speech are restored/cleared in teardown.
final class VoiceAutoRoutingIntegrationTests: XCTestCase {
    private var oldIdleTimer = false
    private var savedPreferences: [String: Any] = [:]
    private var savedArguments: [String: Any] = [:]
    private let preferenceKeys = [AutoTranslation.preferenceKey, "selectedTranslationModel", "voice.th", "liveDownloadIDs"]
    private var pipelineToUnload: ConversationPipeline?
    private var recorderToCancel: AudioRecorder?
    private var speechToUnload: SherpaSpeechBackend?
    private var downloadProbes: [ModelDownloader] = []
    @MainActor override func setUp() async throws {
        let defaults = UserDefaults.standard
        for key in preferenceKeys { savedPreferences[key] = defaults.object(forKey: key) }
        savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        oldIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }
    @MainActor override func tearDown() async throws {
        recorderToCancel?.cancel()
        await pipelineToUnload?.unload(); pipelineToUnload?.clearTemporarySpeech()
        await speechToUnload?.unload()
        for downloader in downloadProbes {
            if downloader.installedURL != nil { await downloader.remove() }
            else { await downloader.cancel() }
            try? FileManager.default.removeItem(at: downloader.transferRoot)
        }
        let defaults = UserDefaults.standard
        let packages = PackageDownloadCoordinator.shared
        packages.selectTranslation(TranslationModel.restoredSelection(savedPreferences["selectedTranslationModel"] as? String))
        packages.setAutoTranslation(savedPreferences[AutoTranslation.preferenceKey] as? Bool ?? (savedPreferences["selectedTranslationModel"] == nil))
        for key in preferenceKeys {
            if let value = savedPreferences[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
        UIApplication.shared.isIdleTimerDisabled = oldIdleTimer
    }
    /// Opt-in migration check: the host provides a private manifest of the old
    /// container's byte-stable files. Verify bytes without exporting another model copy.
    /// Compare history.json semantically on the host: startup rewrites JSON key order.
    @MainActor func testMigratedFilesMatchSHA256Manifest() async throws {
        struct Entry: Decodable, Sendable { let path: String; let bytes: Int64; let sha256: String }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let manifest = home.appendingPathComponent("Documents/KatMigrationVerification.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip("Migration manifest is opt-in and must not ship in the app bundle")
        }
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.kattranslator")
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: manifest))
        XCTAssertFalse(entries.isEmpty)
        executionTimeAllowance = 1800
        let verified = try await Task.detached(priority: .utility) {
            var count = 0
            for entry in entries {
                try Task.checkCancellation()
                guard !entry.path.hasPrefix("/"), !entry.path.split(separator: "/").contains(".."),
                      entry.path.hasPrefix("Documents/") || entry.path.hasPrefix("Library/Application Support/OfflineTranslator/") else {
                    throw NSError(domain: "KatMigration", code: 1)
                }
                let url = home.appendingPathComponent(entry.path)
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink == false,
                      Int64(values.fileSize ?? -1) == entry.bytes else {
                    throw NSError(domain: "KatMigration", code: 2, userInfo: [NSLocalizedDescriptionKey: entry.path])
                }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var hash = SHA256()
                while try autoreleasepool(invoking: {
                    let data = try file.read(upToCount: 1_048_576) ?? Data()
                    guard !data.isEmpty else { return false }
                    hash.update(data: data); return true
                }) {}
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else {
                    throw NSError(domain: "KatMigration", code: 3, userInfo: [NSLocalizedDescriptionKey: entry.path])
                }
                count += 1
            }
            return count
        }.value
        XCTAssertEqual(verified, entries.count)
        print("KAT_MIGRATION_HASH_VERIFIED", verified, "files", entries.reduce(Int64(0)) { $0 + $1.bytes }, "bytes")
        try FileManager.default.removeItem(at: manifest) // Only this test-owned input.
    }
    @MainActor private func fixture(_ language: String) throws -> CapturedAudio {
        try AudioFileImport.read(try XCTUnwrap(Bundle.main.url(forResource: "sherpa-onnx-supertonic-3-tts-int8-2026-05-11-" + language, withExtension: "m4a")))
    }
    @MainActor private func prepare(_ initial: TranslationModel = .opusBig) async throws -> ConversationPipeline {
        let defaults = UserDefaults.standard
        // A process-local override exercises compact Auto; never overwrite the saved probe.
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["deviceProbeResult"] = ""; defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let packages = PackageDownloadCoordinator.shared
        await packages.restore(); packages.setAutoTranslation(true)
        let pipeline = ConversationPipeline(asr: RoutedASRBackend(), translator: RoutedTranslationBackend(),
            speech: SherpaSpeechBackend(), player: SpeechPlayer())
        pipelineToUnload = pipeline
        await pipeline.prepare(PipelineFiles(asr: try XCTUnwrap(packages.primaryRecognition(for: .automatic)),
            translation: try XCTUnwrap(packages.translationURL(for: initial)),
            voices: packages.selectedVoiceDirectories, voiceModelIDs: packages.selectedVoiceModelIDs,
            translationModel: initial, translationResolver: try XCTUnwrap(packages.translationResolver)), memorySaving: false)
        XCTAssertTrue(pipeline.isReady, pipeline.error ?? "Preparation failed")
        return pipeline
    }
    @MainActor private func check(_ pipeline: ConversationPipeline, _ language: SpeechLanguage, _ model: TranslationModel) {
        XCTAssertNil(pipeline.voiceFields.error)
        XCTAssertEqual(pipeline.voiceFields.resolvedSource, language)
        XCTAssertEqual(pipeline.voiceFields.resolvedTarget, .english)
        XCTAssertEqual(pipeline.samples.last?.translationModelID, model.rawValue)
        XCTAssertTrue(pipeline.voiceFields.sourceText.localizedCaseInsensitiveContains(language == .german ? "Zug" : "поезд"), pipeline.voiceFields.sourceText)
        XCTAssertTrue(pipeline.voiceFields.translatedText.localizedCaseInsensitiveContains("train"), pipeline.voiceFields.translatedText)
        XCTAssertTrue(pipeline.hasOriginalRecording)
        XCTAssertNil(pipeline.voiceFields.lastHistoryID)
        print("KAT_VOICE_RESULT", language.rawValue, model.rawValue, pipeline.voiceFields.sourceText, "=>", pipeline.voiceFields.translatedText)
    }
    @MainActor private func logAudioState(_ stage: String) {
        let session = AVAudioSession.sharedInstance()
        // Port types only: device names and identifiers do not belong in test diagnostics.
        print("KAT_AUDIO_STATE", stage, "category", session.category.rawValue,
            "rate", session.sampleRate, "otherAudio", session.isOtherAudioPlaying,
            "outputs", session.currentRoute.outputs.map { $0.portType.rawValue })
    }
    @MainActor func testRepeatedSpeechPlayback() async throws {
        let player = SpeechPlayer()
        defer { player.stop() }
        let pcm = SpeechPCM(samples: (0..<4800).map { Float(sin(Double($0) * 2 * .pi * 440 / 24000)) * 0.02 }, sampleRate: 24000)
        for index in 0..<6 {
            logAudioState("playback-\(index)-before")
            try await player.play(pcm)
            player.stop()
            logAudioState("playback-\(index)-after")
        }
    }
    @MainActor func testAfterStopDetectsLanguageAndSwitchesAutoModels() async throws {
        let pipeline = try await prepare()
        for (language, model) in [(SpeechLanguage.russian, TranslationModel.opusBig), (.german, .index9B), (.russian, .opusBig)] {
            print("KAT_HOST_STATE", UIApplication.shared.applicationState.rawValue, "autoload", UserDefaults.standard.bool(forKey: "automaticModelLoad"))
            let audio = try fixture(language.rawValue)
            logAudioState("auto-\(language.rawValue)-before")
            await pipeline.runRecording(audio: audio, speechEnd: audio.samples.count, source: nil, target: .english,
                speakResult: true, inputMode: "synthetic-recording", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
                requestedPreview: false, fallbackReason: nil)
            logAudioState("auto-\(language.rawValue)-after")
            check(pipeline, language, model)
            XCTAssertTrue(pipeline.hasVoiceTranslationSpeech, pipeline.voiceFields.speechNotice ?? "Missing TTS")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let speech = try XCTUnwrap(pipeline.copyVoiceTranslationSpeech(into: directory))
            XCTAssertGreaterThan(try AVAudioFile(forReading: speech).length, 0)
        }
        await pipeline.unload(); pipeline.clearTemporarySpeech()
    }
    @MainActor func testPreviewResolvesActualLanguageBeforeTranslation() async throws {
        let pipeline = try await prepare(.index9B)
        let audio = try fixture("ru")
        XCTAssertTrue(pipeline.beginRecordingPreview(source: nil, target: .english, speakResult: false,
            snapshot: { range in CapturedAudio(samples: Array(audio.samples[range])) }))
        pipeline.offerRecordingBoundary(audio.samples.count)
        // Finish joins actual ASR/MT preview work; no mocked transcript or translation.
        await pipeline.runRecording(audio: audio, speechEnd: audio.samples.count, source: nil, target: .english,
            speakResult: false, inputMode: "synthetic-preview", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: true, fallbackReason: nil)
        check(pipeline, .russian, .opusBig)
        XCTAssertGreaterThan(pipeline.samples.last?.previewBlocks ?? 0, 0)
        XCTAssertEqual(pipeline.samples.last?.processingMode, "during-recording")
        await pipeline.unload(); pipeline.clearTemporarySpeech()
    }
    /// Real HTTPS downloads through the production background URLSession and
    /// SHA-256 installation path. Unique IDs keep existing model files intact.
    @MainActor func testModelDownloadsWithoutOpenSSL() async throws {
        executionTimeAllowance = 600
        for source in [ModelCatalog.wayuStyles, ModelCatalog.wayuCurves] {
            let model = ModelDescriptor(id: "kat-openssl-probe-" + UUID().uuidString.lowercased(),
                title: "Download verification", remoteURL: source.remoteURL,
                byteCount: source.byteCount, sha256: source.sha256)
            let downloader = ModelDownloader(model: model)
            downloadProbes.append(downloader)
            await downloader.restore()
            XCTAssertNil(downloader.installedURL)
            let started = Date()
            downloader.start()
            while downloader.installedURL == nil, downloader.state.phase != .failed,
                  Date().timeIntervalSince(started) < 240 {
                try await Task.sleep(for: .milliseconds(250))
            }
            XCTAssertEqual(downloader.state.phase, .installed, downloader.state.error ?? "Download timed out")
            let installed = try XCTUnwrap(downloader.installedURL)
            let data = try Data(contentsOf: installed)
            XCTAssertEqual(Int64(data.count), source.byteCount)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), source.sha256)
            print("KAT_HTTPS_MODEL_PASS", source.id, data.count, "seconds", Date().timeIntervalSince(started))
        }
    }
    @MainActor func testThaiWayuSynthesisWithoutOpenSSL() async throws {
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        packages.selectVoice(packages.wayuVoice, language: .thai)
        let directory = try XCTUnwrap(packages.selectedVoiceDirectories[.thai])
        XCTAssertTrue(directory.fragment?.hasPrefix("wayu:") == true)
        for name in ["_ssl", "_hashlib"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(name).framework").path))
        }
        let speech = SherpaSpeechBackend(); speechToUnload = speech
        try await speech.load(directory: directory, language: .thai)
        let player = SpeechPlayer()
        defer { player.stop() }
        for text in ["สวัสดีค่ะ สบายดีไหมคะ?", "ราคา 250 บาท", "เรียก Grab"] {
            let start = Date()
            let pcm = try await speech.synthesize(text: text)
            XCTAssertEqual(pcm.sampleRate, 24000)
            XCTAssertGreaterThan(pcm.samples.count, 2400)
            XCTAssertTrue(pcm.samples.allSatisfy { $0.isFinite })
            XCTAssertGreaterThan(pcm.samples.map(abs).max() ?? 0, 0.001)
            print("KAT_WAYU_PASS", text, "samples", pcm.samples.count, "seconds", Date().timeIntervalSince(start))
            try await player.play(pcm)
        }
        do {
            _ = try await speech.synthesize(text: "สวัสดี xyzqqzz")
            XCTFail("Unknown English word must be rejected")
        } catch { print("KAT_WAYU_UNKNOWN_WORD_REJECTED") }
        await speech.unload()
    }
    @MainActor func testRecognizedRussianTranslatesAndSpeaksThai() async throws {
        let packages = PackageDownloadCoordinator.shared
        await packages.restore()
        packages.selectVoice(packages.wayuVoice, language: .thai)
        let pipeline = try await prepare()
        let audio = try fixture("ru")
        logAudioState("thai-pipeline-before")
        await pipeline.runRecording(audio: audio, speechEnd: audio.samples.count, source: nil, target: .thai,
            speakResult: true, inputMode: "synthetic-recording", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
            requestedPreview: false, fallbackReason: nil)
        logAudioState("thai-pipeline-after")
        XCTAssertNil(pipeline.voiceFields.error)
        XCTAssertEqual(pipeline.voiceFields.resolvedSource, .russian)
        XCTAssertEqual(pipeline.voiceFields.resolvedTarget, .thai)
        XCTAssertEqual(pipeline.samples.last?.translationModelID, TranslationModel.index9B.rawValue)
        XCTAssertTrue(pipeline.voiceFields.sourceText.localizedCaseInsensitiveContains("поезд"))
        XCTAssertTrue(pipeline.voiceFields.translatedText.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
        XCTAssertTrue(pipeline.hasVoiceTranslationSpeech, pipeline.voiceFields.speechNotice ?? "Missing Thai TTS")
        XCTAssertNil(pipeline.voiceFields.lastHistoryID)
        print("KAT_THAI_PIPELINE_PASS", pipeline.voiceFields.translatedText)
        await pipeline.unload(); pipeline.clearTemporarySpeech()
    }
    @MainActor func testMicrophoneDetectsPeerSpeechAndSwitchesAutoModels() async throws {
        let pipeline = try await prepare()
        let recorder = AudioRecorder(); recorderToCancel = recorder
        for (language, model) in [(SpeechLanguage.german, TranslationModel.index9B), (.russian, .opusBig)] {
            await pipeline.preloadRecognition(source: nil)
            try await recorder.start(silenceSeconds: 60, limitMinutes: 1)
            print("KAT_IPHONE_MIC_READY", language.rawValue); fflush(stdout)
            try await Task.sleep(for: .seconds(25))
            let audio = try await recorder.stop()
            XCTAssertGreaterThan(audio.samples.map(abs).max() ?? 0, 0.005, "Peer speaker must reach microphone")
            await pipeline.runRecording(audio: audio, speechEnd: recorder.finalSpeechEnd, source: nil, target: .english,
                speakResult: false, inputMode: "physical-microphone", thermal: "nominal", stoppedAt: ProcessInfo.processInfo.systemUptime,
                requestedPreview: false, fallbackReason: nil)
            check(pipeline, language, model)
        }
        await pipeline.unload(); pipeline.clearTemporarySpeech()
    }
    /// Host copies only synthetic fixture commands into this test-owned temporary directory.
    @MainActor func testSpeakerForPixelMicrophone() async throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("KatVoicePeerTest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true)
        defer { try? session.setActive(false) }
        print("KAT_IPHONE_SPEAKER_READY"); fflush(stdout)
        for number in 0..<3 {
            let command = directory.appendingPathComponent("\(number).txt")
            let deadline = Date().addingTimeInterval(120)
            while !FileManager.default.fileExists(atPath: command.path), Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
            let language = try String(contentsOf: command).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(["ru", "de"].contains(language))
            let url = try XCTUnwrap(Bundle.main.url(forResource: "sherpa-onnx-supertonic-3-tts-int8-2026-05-11-" + language, withExtension: "m4a"))
            let player = try AVAudioPlayer(contentsOf: url); player.volume = 1
            XCTAssertTrue(player.play())
            while player.isPlaying { try await Task.sleep(for: .milliseconds(100)) }
            print("KAT_IPHONE_SPEAKER_DONE", number, language); fflush(stdout)
        }
    }
}
