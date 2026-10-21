// Opt-in physical-device acceptance with ordinary saved app settings.
// Supply a continuous spoken fixture after KAT_PREVIEW_MIC_READY. No launch overrides.
// This creates a normal recording/history entry; retain device data and private captures.
import XCTest
final class VoicePreviewDeviceTests: XCTestCase {
 @MainActor func capture(_ app: XCUIApplication, _ name: String) {
  let tree=XCTAttachment(string:app.debugDescription);tree.name=name+"-tree";tree.lifetime = .keepAlways;add(tree)
  let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }
 @MainActor func testContinuousRecordingPreview() throws {
  continueAfterFailure=true
  let app=XCUIApplication(bundleIdentifier:"app.kattranslator")
  app.launchArguments=[]
  app.launch()
  defer { capture(app,"ordinary-preview-final-state"); app.terminate(); app.launch() }
  let prepare=app.buttons["voice.prepare"]
  if prepare.waitForExistence(timeout:5) && prepare.isEnabled {prepare.tap()}
  let record=app.buttons["voice.record"]
  XCTAssertTrue(record.waitForExistence(timeout:120))
  XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:record)],timeout:120),.completed)
  record.tap()
  XCTAssertTrue(app.buttons["voice.pauseResume"].waitForExistence(timeout:10))
  print("KAT_PREVIEW_MIC_READY")
  let started=Date()
  let translated=app.staticTexts["voice.translation.text"]
  let visible=translated.waitForExistence(timeout:45)
  XCTAssertTrue(visible)
  guard visible else { return }
  XCTAssertTrue(app.staticTexts["recording.preview"].exists)
  XCTAssertTrue(app.buttons["voice.pauseResume"].isHittable)
  XCTAssertTrue(record.isHittable)
  XCTAssertTrue(app.staticTexts["voice.recording.time"].exists)
  let first=translated.label
  XCTAssertFalse(first.isEmpty)
  print("KAT_PREVIEW_FIRST_SECONDS=\(Date().timeIntervalSince(started))")
  capture(app,"ordinary-preview-first-during-continuous-speech")
  let grows=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
    translated.exists && translated.label.count > first.count
  },object:nil)
  XCTAssertEqual(XCTWaiter.wait(for:[grows],timeout:25),.completed)
  XCTAssertTrue(app.buttons["voice.pauseResume"].isHittable)
  XCTAssertTrue(app.staticTexts["voice.recording.time"].exists)
  print("KAT_PREVIEW_GROWTH_SECONDS=\(Date().timeIntervalSince(started))")
  capture(app,"ordinary-preview-grew-before-stop")
  while Date().timeIntervalSince(started)<74 { Thread.sleep(forTimeInterval:1) }
  capture(app,"ordinary-preview-full-clip-before-stop")
  if app.staticTexts["voice.recording.time"].exists && record.exists { record.tap() }
  else { print("KAT_RECORDING_AUTO_STOPPED") }
  Thread.sleep(forTimeInterval:3)
 }
}
