import XCTest

final class LoadingAnimationTests: XCTestCase {
    func testWaitingClipsAreNotBundled() {
        for name in ["cat-wizard", "loading-cat-paw", "loading-wizard"] {
            XCTAssertNil(Bundle.main.url(forResource: name, withExtension: "mp4"))
        }
        XCTAssertNil(Bundle.main.url(forResource: "loading-animations", withExtension: "json"))
    }
}
