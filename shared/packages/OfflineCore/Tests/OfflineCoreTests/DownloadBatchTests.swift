import XCTest
@testable import OfflineCore
final class DownloadBatchTests: XCTestCase {
    func testCompletedAndSharedFilesPresentBeforeBatchAreProtected() throws {
        var batch = DownloadBatch()
        batch.include([.init(id:"old-voice",bytes:100,installed:true), .init(id:"shared",bytes:200,installed:true), .init(id:"new-voice",bytes:50,installed:false), .init(id:"mt",bytes:900,installed:false)])
        XCTAssertEqual(batch.ids, ["new-voice","mt"])
        // A pause/relaunch and completion must not turn current-batch files into protected files.
        batch = try JSONDecoder().decode(DownloadBatch.self, from: JSONEncoder().encode(batch))
        batch.include([.init(id:"new-voice",bytes:50,installed:true),.init(id:"mt",bytes:900,installed:false),.init(id:"shared",bytes:200,installed:true)])
        XCTAssertEqual(batch.ids,["new-voice","mt"])
        XCTAssertFalse(batch.ids.contains("old-voice")); XCTAssertFalse(batch.ids.contains("shared"))
    }
    // Audit 22.10 (B5): a batch completed outside the queue must end, so Cancel all cannot delete it later.
    func testBatchIsCompleteOnlyWhenEveryOwnedFileIsInstalled() {
        var batch = DownloadBatch()
        XCTAssertFalse(batch.isComplete(installed: { _ in true }), "an empty batch owns nothing")
        batch.include([.init(id: "index", bytes: 5, installed: false), .init(id: "voice", bytes: 1, installed: false), .init(id: "old", bytes: 1, installed: true)])
        XCTAssertFalse(batch.isComplete(installed: { $0 == "index" }))
        XCTAssertTrue(batch.isComplete(installed: { ["index", "voice"].contains($0) }))
    }
}
