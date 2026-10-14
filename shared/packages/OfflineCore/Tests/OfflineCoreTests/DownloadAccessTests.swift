import XCTest
@testable import OfflineCore

final class DownloadAccessTests: XCTestCase {
    func testOnlyUnmeteredConnectedPathsSkipWarning() {
        XCTAssertFalse(DownloadNetworkState.wifi.requiresConfirmation)
        XCTAssertFalse(DownloadNetworkState.wired.requiresConfirmation)
        XCTAssertTrue(DownloadNetworkState.cellular.requiresConfirmation)
        XCTAssertTrue(DownloadNetworkState.expensive.requiresConfirmation)
        XCTAssertTrue(DownloadNetworkState.offline.requiresConfirmation)
        XCTAssertTrue(DownloadNetworkState.unknown.requiresConfirmation)
        XCTAssertFalse(DownloadNetworkState.offline.canDownload(allowCellular: true))
        XCTAssertFalse(DownloadNetworkState.unknown.canDownload(allowCellular: true))
        XCTAssertFalse(DownloadNetworkState.cellular.canDownload(allowCellular: false))
        XCTAssertTrue(DownloadNetworkState.cellular.canDownload(allowCellular: true))
        XCTAssertTrue(DownloadNetworkState.wifi.canDownload(allowCellular: false))
    }
    func testWarningCountsOnlyNewMissingFilesOnceAndShowsConservativeSize() {
        let items: [DownloadAccessItem] = [
            .init(id: "shared", bytes: 5_780_000_000, phase: .paused, installed: false),
            .init(id: "shared", bytes: 5_780_000_000, phase: .paused, installed: false),
            .init(id: "voice", bytes: 100_000_000, phase: .idle, installed: false),
            .init(id: "ready", bytes: 1_000_000_000, phase: .installed, installed: true),
            .init(id: "checking", bytes: 1_000_000, phase: .checking, installed: false),
            .init(id: "active", bytes: 2_000_000, phase: .downloading, installed: false)
        ]
        XCTAssertEqual(DownloadAccessItem.maximumDownloadBytes(items), 5_880_000_000)
        XCTAssertEqual(DownloadAccessItem.maximumDownloadBytes([]), 0)
    }
    func testResumeNeverKeepsAnOldNetworkPermission() {
        XCTAssertTrue(DownloadAccessItem.canResume(previousCellular: false, allowCellular: false))
        XCTAssertTrue(DownloadAccessItem.canResume(previousCellular: true, allowCellular: true))
        XCTAssertFalse(DownloadAccessItem.canResume(previousCellular: false, allowCellular: true))
        XCTAssertFalse(DownloadAccessItem.canResume(previousCellular: true, allowCellular: false))
        XCTAssertFalse(DownloadAccessItem.canResume(previousCellular: nil, allowCellular: true))
        XCTAssertFalse(DownloadAccessItem.canResume(previousCellular: nil, allowCellular: false))
    }
}
