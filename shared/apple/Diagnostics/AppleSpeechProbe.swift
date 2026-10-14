#if APPLE_SPEECH_PROBE
import Foundation
import Speech
import AVFoundation
import UIKit
import OfflineCore

/// Explicit development build only. Fixed synthetic audio, no history or microphone access.
@MainActor enum AppleSpeechProbe {
    private static func readFixture(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let normalizer = AudioNormalizer()
        var samples: [Float] = []
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
            try file.read(into: buffer)
            samples.append(contentsOf: try normalizer.convert(buffer))
        }
        samples.append(contentsOf: try normalizer.finish())
        return samples
    }
    static func run(packages: PackageDownloadCoordinator, progress: (String) -> Void) async {
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let runID = env["OT_APPLE_ASR_RUN_ID"] ?? UUID().uuidString
        var result: [String: Any] = ["runID": runID, "system": UIDevice.current.systemVersion, "rows": []]
        func save(_ status: String) {
            result["status"] = status
            progress("Apple ASR probe: " + status)
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: root.appendingPathComponent("apple-asr-probe.json"), options: .atomic)
            }
        }
        let oldIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = oldIdle }
        var availability: [[String: Any]] = []
        for code in ["ru-RU", "en-US", "id-ID", "th-TH"] {
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: code))
            availability.append(["locale": code, "supported": SFSpeechRecognizer.supportedLocales().contains { $0.identifier == code },
                                 "onDevice": recognizer?.supportsOnDeviceRecognition ?? false,
                                 "available": recognizer?.isAvailable ?? false])
        }
        result["legacyAvailability"] = availability
        if #available(iOS 26.0, *) {
            result["speechTranscriberLocales"] = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
            result["dictationTranscriberLocales"] = await DictationTranscriber.supportedLocales.map(\.identifier).sorted()
        }
        save("availability")
        guard env["OT_APPLE_ASR_MODE"] != "availability" else { return }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        result["authorization"] = authorization.rawValue
        guard authorization == .authorized else { save("permission-denied"); return }
        let whisper = WhisperBackend()
        var rows: [[String: Any]] = []
        do {
            guard let whisperURL = packages.whisper.installedURL else { save("missing-whisper"); return }
            let start = ProcessInfo.processInfo.systemUptime
            try await whisper.load(modelURL: whisperURL)
            result["whisperLoadSeconds"] = ProcessInfo.processInfo.systemUptime - start
            for (name, locale, language) in [("short", "ru-RU", SpeechLanguage.russian), ("numbers-ru", "ru-RU", .russian), ("medium", "en-US", .english)] {
                let samples = try readFixture(root.appendingPathComponent("AppleSpeechFixtures/" + name + ".aiff"))
                save("whisper-" + name)
                let t = ProcessInfo.processInfo.systemUptime
                let transcript = try await whisper.transcribe(CapturedAudio(samples: samples), language: language)
                rows.append(["engine": "whisper", "fixture": name, "audioSeconds": Double(samples.count) / 16000,
                             "seconds": ProcessInfo.processInfo.systemUptime - t, "text": transcript.text])
                result["rows"] = rows
                save("apple-" + name)
                let runner = AppleSpeechFixtureRun()
                var row = await runner.run(samples: samples, locale: locale, paced: false)
                row["engine"] = "apple-on-device"; row["fixture"] = name
                rows.append(row); result["rows"] = rows; save("completed-" + name)
            }
            await whisper.unload()
            // Deliver audio at capture speed to measure when partial results arrive and the final tail.
            for (name, locale) in [("numbers-ru", "ru-RU"), ("medium", "en-US")] {
                let samples = try readFixture(root.appendingPathComponent("AppleSpeechFixtures/" + name + ".aiff"))
                save("apple-realtime-" + name)
                let runner = AppleSpeechFixtureRun()
                var row = await runner.run(samples: samples, locale: locale, paced: true)
                row["engine"] = "apple-on-device-realtime"; row["fixture"] = name
                rows.append(row); result["rows"] = rows
            }
            save("complete")
        } catch {
            result["error"] = error.localizedDescription; save("failed")
        }
        await whisper.unload()
    }
}

@MainActor private final class AppleSpeechFixtureRun {
    private var speechTask: SFSpeechRecognitionTask?
    private var feeder: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var completion: CheckedContinuation<[String: Any], Never>?
    private var events: [[String: Any]] = []
    private var start = 0.0
    private var ended: Double?
    private var duration = 0.0
    private var text = ""
    func run(samples: [Float], locale: String, paced: Bool) async -> [String: Any] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.supportsOnDeviceRecognition else {
            return ["status": "offline-unsupported", "locale": locale]
        }
        guard recognizer.isAvailable else { return ["status": "unavailable", "locale": locale] }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        start = ProcessInfo.processInfo.systemUptime
        duration = Double(samples.count) / 16000
        return await withCheckedContinuation { continuation in
            completion = continuation
            speechTask = recognizer.recognitionTask(with: request) { result, error in
                let transcript = result?.bestTranscription.formattedString
                let segments: [[String: Any]] = result?.bestTranscription.segments.map {
                    ["text": $0.substring, "start": $0.timestamp, "duration": $0.duration, "confidence": $0.confidence]
                } ?? []
                let metadataStart = result?.speechRecognitionMetadata?.speechStartTimestamp
                let metadataDuration = result?.speechRecognitionMetadata?.speechDuration
                let final = result?.isFinal ?? false
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.completion != nil else { return }
                    if let transcript {
                        self.text = transcript
                        var event: [String: Any] = ["seconds": ProcessInfo.processInfo.systemUptime - self.start,
                                                  "text": transcript, "final": final, "segments": segments]
                        if let metadataStart { event["speechStart"] = metadataStart }
                        if let metadataDuration { event["speechDuration"] = metadataDuration }
                        self.events.append(event)
                    }
                    if final { self.finish(status: "complete") }
                    else if let failure { self.finish(status: "error", error: failure) }
                }
            }
            feeder = Task { @MainActor in
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                for offset in stride(from: 0, to: samples.count, by: 1600) {
                    guard !Task.isCancelled, completion != nil else { return }
                    let count = min(1600, samples.count - offset)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                    buffer.frameLength = AVAudioFrameCount(count)
                    samples.withUnsafeBufferPointer { source in
                        buffer.floatChannelData![0].update(from: source.baseAddress!.advanced(by: offset), count: count)
                    }
                    request.append(buffer)
                    if paced { try? await Task.sleep(nanoseconds: 100_000_000) }
                    else { await Task.yield() }
                }
                ended = ProcessInfo.processInfo.systemUptime
                request.endAudio()
            }
            timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((paced ? duration + 30 : 45) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                finish(status: "timeout")
            }
        }
    }
    private func finish(status: String, error: String? = nil) {
        guard let completion else { return }
        self.completion = nil
        let now = ProcessInfo.processInfo.systemUptime
        var row: [String: Any] = ["status": status, "seconds": now - start, "audioSeconds": duration,
                                  "text": text, "events": events, "onDeviceRequired": true,
                                  "thermal": AppModel.thermalState]
        if let ended { row["afterEndSeconds"] = now - ended }
        if let error { row["error"] = error }
        feeder?.cancel(); timeout?.cancel(); speechTask?.cancel(); speechTask = nil
        completion.resume(returning: row)
    }
}
#endif
