import XCTest
import AVFoundation
import AppKit
@testable import Kat_translator

final class LoadingAnimationTests: XCTestCase {
    func testBundledClipsAreSilentAndHaveMatchingPosters() async throws {
        let clips = LoadingAnimation.available
        XCTAssertEqual(clips.count, 13)
        XCTAssertFalse(clips.contains { $0.id == "one-beer" })
        XCTAssertFalse(clips.contains { $0.id == "film-drink" })
        XCTAssertEqual(Set(clips.map(\.id)).count, clips.count)
        XCTAssertTrue(clips.contains { $0.id == "wizard" })
        for clip in clips {
            let asset = AVURLAsset(url: try XCTUnwrap(clip.videoURL))
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(audio.isEmpty, clip.id)
            let video = try await asset.loadTracks(withMediaType: .video)
            let size = try await XCTUnwrap(video.first).load(.naturalSize)
            XCTAssertEqual(size, CGSize(width: 384, height: 288), clip.id)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, clip.duration, accuracy: 0.1, clip.id)
            let poster = try NSBitmapImageRep(data: Data(contentsOf: XCTUnwrap(clip.posterURL)))
            XCTAssertEqual(poster?.pixelsWide, 384, clip.id)
            XCTAssertEqual(poster?.pixelsHigh, 288, clip.id)
        }
    }

    @MainActor func testShuffleVisitsEveryClipWithoutConsecutiveRepeats() throws {
        let clips = LoadingAnimation.available
        let deck = LoadingAnimationDeck(animations: clips)
        var previous: String?
        for _ in 0..<100 {
            var seen = Set<String>()
            for _ in clips {
                let clip = try XCTUnwrap(deck.next())
                XCTAssertNotEqual(clip.id, previous)
                XCTAssertTrue(seen.insert(clip.id).inserted)
                previous = clip.id
            }
            XCTAssertEqual(seen, Set(clips.map(\.id)))
        }
        XCTAssertNil(LoadingAnimationDeck(animations: []).next())
        let only = try XCTUnwrap(clips.first)
        let single = LoadingAnimationDeck(animations: [only])
        XCTAssertEqual(single.next(), only)
        XCTAssertEqual(single.next(), only)
    }

    @MainActor func testRealPlaybackRotatesAtEndAndReleasesDecoder() async throws {
        let clips = LoadingAnimation.available.filter { ["monkey-work", "cat-paw"].contains($0.id) }
        XCTAssertEqual(clips.count, 2)
        var playback: LoadingAnimationPlayback? = LoadingAnimationPlayback(
            deck: LoadingAnimationDeck(animations: clips))
        weak var weakPlayback = playback
        let player = try XCTUnwrap(playback?.player)
        let first = try XCTUnwrap(playback?.animation)
        XCTAssertTrue(player.isMuted)
        XCTAssertEqual(player.volume, 0)
        XCTAssertEqual(player.rate, 0)
        playback?.setRunning(true)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(playback?.animation, first, "Do not interrupt a clip mid-playback")
        playback?.setRunning(false)
        let pausedAt = player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(player.currentTime().seconds, pausedAt, accuracy: 0.08)
        playback?.setRunning(true)
        // The production default must advance after the first play, without an 8s hold.
        for _ in 0..<45 where playback?.animation == first {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotEqual(playback?.animation, first, "A finished clip should select the next one")
        playback?.dispose()
        playback?.setRunning(true)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.rate, 0)
        playback = nil
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(weakPlayback, "Observers/seek callbacks must not retain a dismissed loader")
        XCTAssertNil(player.currentItem)
    }

    @MainActor func testNativeSurfaceShowsNewVideoAfterClipChangeAndPauses() async throws {
        let surface = MacWizardSurface()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 288),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface; window.makeKeyAndOrderFront(nil)
        defer { surface.dispose(); window.close() }
        let layer = try XCTUnwrap(surface.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first)
        let poster = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertNotNil(poster.image)
        XCTAssertFalse(poster.isHidden)
        let firstItem = try XCTUnwrap(layer.player?.currentItem)
        surface.setRunning(true)
        for _ in 0..<50 where !poster.isHidden { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(layer.isReadyForDisplay)
        XCTAssertTrue(poster.isHidden, "Poster must give way to video")
        for _ in 0..<200 where layer.player?.currentItem === firstItem {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(layer.player?.currentItem === firstItem)
        for _ in 0..<50 where !poster.isHidden { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(layer.isReadyForDisplay)
        XCTAssertTrue(poster.isHidden, "Poster must not cover the next clip forever")
        surface.setRunning(false)
        XCTAssertFalse(poster.isHidden)
        XCTAssertEqual(layer.player?.rate, 0)
        surface.dispose()
        XCTAssertNil(layer.player)
    }
}
