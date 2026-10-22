import XCTest

/// Drives the already running Kat Audit Lab without relaunching it (activate, not launch).
/// LAB_ACTIONS: steps separated by ";" — id:<accessibility id>, label:<visible text>, xy:<x>,<y> (points),
/// app:<bundle id or lab>, portrait, home, siri:<text>, sys:<system alert button>, type:<text>, swipeup, swipedown, wait:<seconds>, dump (prints the element tree). Each tap scrolls up to 10 times to reach it.
final class LabDriverUITests: XCTestCase {
    @MainActor func testActions() throws {
        guard let actions = ProcessInfo.processInfo.environment["LAB_ACTIONS"] else { throw XCTSkip("No LAB_ACTIONS") }
        continueAfterFailure = false
        var app = XCUIApplication(bundleIdentifier: "app.kattranslator.voicelab")
        app.activate()
        for step in actions.split(separator: ";").map(String.init) {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let value = parts.count > 1 ? parts[1] : ""
            print("LAB_STEP \(step)")
            switch parts[0] {
            case "id": try tap(app.descendants(matching: .any).matching(identifier: value).firstMatch, in: app, step)
            case "label":
                try tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", value)).firstMatch, in: app, step)
            case "xy":
                let xy = value.split(separator: ",").compactMap { Double($0) }
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            case "app": // switch the target app, e.g. com.apple.Preferences; "lab" returns to Kat Audit Lab
                app = XCUIApplication(bundleIdentifier: value == "lab" ? "app.kattranslator.voicelab" : value)
                app.activate()
            case "sys": // a system alert button, e.g. the notification permission prompt
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                let button = springboard.alerts.buttons[value]
                if button.waitForExistence(timeout: 5) { button.tap() } else { print("LAB_MISSING \(step)") }
            case "type": app.typeText(value) // into the focused field
            case "portrait": XCUIDevice.shared.orientation = .portrait
            case "home": XCUIDevice.shared.press(.home) // the lab goes to the background
            case "siri": XCUIDevice.shared.siriService.activate(voiceRecognitionText: value) // an audio interruption
            case "swipeup": app.swipeUp()
            case "swipedown": app.swipeDown()
            case "wait": Thread.sleep(forTimeInterval: Double(value) ?? 1)
            case "dump": print("LAB_DUMP_BEGIN\n\(app.debugDescription)\nLAB_DUMP_END")
            default: XCTFail("Unknown step \(step)")
            }
        }
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication, _ step: String) throws {
        guard element.waitForExistence(timeout: 15) else { print("LAB_MISSING \(step)"); throw XCTSkip("Missing \(step)") }
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        element.tap()
    }
}
