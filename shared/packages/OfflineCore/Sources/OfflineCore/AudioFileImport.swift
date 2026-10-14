import AVFoundation

public enum AudioFileImportError: LocalizedError {
    case unreadable, tooShort, tooLong(minutes: Int)
    public var errorDescription: String? {
        switch self {
        case .unreadable: return L10n.text("Не удалось прочитать аудиофайл. Выберите другую запись, например MP3, M4A или WAV.")
        case .tooShort: return L10n.text("Аудиофайл пустой или слишком короткий.")
        case .tooLong(let minutes): return L10n.text("Аудиофайл слишком длинный. Максимальная длительность — \(minutes) мин.")
        }
    }
}

public enum AudioFileImport {
    /// Decode in bounded blocks on a worker task. Keep the entire recording at
    /// recognition's 16 kHz mono rate; never silently trim a file to the limit.
    public static func read(_ url: URL, maximumSeconds: Double = RecordingPolicy.maximumMinutes * 60) throws -> CapturedAudio {
        try Task.checkCancellation()
        guard maximumSeconds.isFinite, maximumSeconds > 0, maximumSeconds <= RecordingPolicy.maximumMinutes * 60 else {
            throw AudioFileImportError.unreadable
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else { throw AudioFileImportError.unreadable }
            let duration = Double(file.length) / format.sampleRate
            guard duration.isFinite, duration >= 0.25 else { throw AudioFileImportError.tooShort }
            let tooLong = AudioFileImportError.tooLong(minutes: Int(ceil(maximumSeconds / 60)))
            guard duration <= maximumSeconds else { throw tooLong }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw AudioFileImportError.unreadable }
            let normalizer = AudioNormalizer()
            let maximumSamples = Int(maximumSeconds * 16000)
            var samples: [Float] = []
            samples.reserveCapacity(min(maximumSamples, Int(ceil(duration * 16000))))
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: buffer.frameCapacity)
                guard buffer.frameLength > 0 else { throw AudioFileImportError.unreadable }
                samples.append(contentsOf: try normalizer.convert(buffer))
                guard samples.count <= maximumSamples else { throw tooLong }
            }
            samples.append(contentsOf: try normalizer.finish())
            try Task.checkCancellation()
            guard samples.count <= maximumSamples else { throw tooLong }
            guard samples.count >= 4000 else { throw AudioFileImportError.tooShort }
            return CapturedAudio(samples: samples)
        } catch is CancellationError { throw CancellationError() }
        catch let error as AudioFileImportError { throw error }
        catch { throw AudioFileImportError.unreadable }
    }
}
