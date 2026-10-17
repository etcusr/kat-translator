import XCTest
@testable import OfflineCore

@MainActor final class StreamedSpeechStartTests: XCTestCase {
    func testRewrittenPrefixDoesNotPlayPendingOldSentence() async {
        let stream = StreamedSpeechStart()
        var gate: CheckedContinuation<Void, Never>?
        var played: [String] = []
        let prepare: @MainActor (String) async throws -> RecordingPreviewSpeech? = { text in
            await withCheckedContinuation { gate = $0 }
            return RecordingPreviewSpeech(text: text, pcm: SpeechPCM(samples: [0.1], sampleRate: 22050), seconds: 0)
        }
        let play: @MainActor (RecordingPreviewSpeech) -> Task<Void, Error> = { part in
            played.append(part.text); return Task { }
        }
        stream.offer("Old first sentence. Pending", prepare: prepare, play: play)
        while gate == nil { await Task.yield() }
        stream.offer("New first sentence. Pending", prepare: prepare, play: play)
        gate?.resume(); await stream.finish()
        XCTAssertEqual(played, [])
        XCTAssertNil(stream.speech)
    }
    func testCancelWhileWaitingForPlaybackDoesNotStartNextSentence() async {
        let stream = StreamedSpeechStart()
        var prepared = 0
        var gate: CheckedContinuation<Void, Never>?
        var played: [String] = []
        stream.offer("First sentence here. Second sentence here. Pending", prepare: { text in
            prepared += 1
            return RecordingPreviewSpeech(text: text, pcm: SpeechPCM(samples: [0.1], sampleRate: 22050), seconds: 0)
        }, play: { part in
            played.append(part.text)
            return Task { if played.count == 1 { await withCheckedContinuation { gate = $0 } } }
        })
        while prepared < 2 || gate == nil { await Task.yield() }
        stream.cancel(); gate?.resume(); await stream.finish()
        XCTAssertEqual(played, ["First sentence here."])
    }
}
