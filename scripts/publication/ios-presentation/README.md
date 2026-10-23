# iPhone presentation scenes

**English** | [Русский](README.ru.md)

Prepared original/translation text for Voice and an example sign for Image, rendered by the actual SwiftUI screens. These are **presentation fixtures**, not recognition, translation, playback or camera acceptance tests. No model inference is needed. The fixture enables result controls for the captured state; it is not a functional app.

`prepare.py --output .build/<new-directory>` copies committed Apple sources into a new ignored directory and patches only that copy. Dependencies are read through a symlink; weights and installed device data are not copied or changed. A compile-time guard rejects physical-device builds. The shipping source and existing Store packages are untouched.

Build the copied `source/apps/ios/OfflineTranslator.xcodeproj` with `-sdk iphonesimulator`, Debug and `CODE_SIGNING_ALLOWED=NO`, using a separate DerivedData directory. Use the dedicated Kat iPhone 17 Pro simulator, never a phone. Shut down native Mac Kat first and acquire the shared heavy-job lock. Generate the independent runner with `scripts/simulator/run.py --screenshots --prepare-only`, replacing its reference to `PublicationScreenshots.swift` with this directory's `Screenshots.swift`.

Install the fixture only in that simulator, run the four `PublicationScreenshots` tests, and export XCTest attachments. Require four passes, no failures/skips and eight named PNGs. Inspect the images. Pass the attachment directory as `--ios-presentation` to `collect-interface-captures.py`; the manifest and gallery identify prepared scenes separately from actual inference captures. Never use fixture timings or controls as performance/behavior evidence.

After capture, reinstall the ordinary app from `.build/SimulatorDerivedData/Build/Products/Debug-iphonesimulator/OfflineTranslator.app` over the fixture (no uninstall/data deletion), restore the ordinary test runner, and shut down the simulator. Keep the provenance JSON and local test result. Do not distribute or upload this fixture build.

The collector keeps only Voice captures in the current presentation set; camera screenshots were excluded by the owner on 23 October.
