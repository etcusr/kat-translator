// Manual fixture for a separate UI-test runner. Compile Kat with the opt-in
// DOWNLOAD_VALIDATION flag; normal builds exclude the diagnostic path.
// Voice mode downloads Denis + a Parakeet component (79.83 MB total).
// The host must verify the JSON report; UI runner success alone is insufficient.
// Run cleanup afterward, then
// reinstall/launch the normal build in place. Never remove the Kat container.
import XCTest
final class DownloadBatchDeviceTests: XCTestCase {
 @MainActor func capture(_ app: XCUIApplication, _ name: String) {
  let tree=XCTAttachment(string:app.debugDescription); tree.name=name+"-tree"; tree.lifetime = .keepAlways; add(tree)
  let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot()); shot.name=name; shot.lifetime = .keepAlways; add(shot)
 }
 @MainActor func testSmallBackground() throws {
  continueAfterFailure=false
  let app=XCUIApplication(bundleIdentifier:"app.kattranslator")
  app.launchEnvironment["OT_DOWNLOAD_VALIDATION"]="voice"
  app.launch()
  XCUIDevice.shared.press(.home)
  Thread.sleep(forTimeInterval:20)
  capture(XCUIApplication(bundleIdentifier:"com.apple.springboard"),"small-background-complete")
  app.activate();capture(app,"small-return")
  // Completion is asserted from Documents/download-validation.json by the host.
 }
 @MainActor func testSmallCleanup() throws {
  let app=XCUIApplication(bundleIdentifier:"app.kattranslator")
  app.launchEnvironment["OT_DOWNLOAD_VALIDATION"]="cleanup-voice"
  app.launch()
  Thread.sleep(forTimeInterval:5) // Host verifies the cleanup report.
  app.terminate()
 }
}
