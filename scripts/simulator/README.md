# Kat UI checks in iOS Simulator

**English** | [Русский](README.ru.md)

Run the real iOS app and repeatable navigation checks without connecting a phone. The runner creates or reuses a dedicated **Kat iPhone 17 Pro** simulator using a compatible installed runtime, builds the normal app for ARM64 Simulator and installs it there. It never erases a device or installs on a physical phone. Existing Mac/iPhone apps and downloaded models are outside this workflow.

## Requirements and first run

Use the project's configured Xcode and prepared native dependencies. Install the compatible ARM64 iOS runtime once:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64
```

The runner requires the exact iPhone 17 Pro device profile. It selects the newest installed runtime advertising support for that profile (iOS 27.0 with the current Xcode). The iOS 27.1 runtime here supports only iPhone Duo; existing Duo devices/runtimes are retained and are not silently substituted.

The runtime download can be several gigabytes, with additional disk space needed for installation. `run.py` does not silently download a runtime or models. Native XCFrameworks must contain their iOS Simulator variants; a successful device build alone does not establish simulator support.

From the repository root:

```sh
python3 scripts/simulator/run.py
```

The command selects the newest installed iOS runtime supporting iPhone 17 Pro, boots its dedicated simulator, opens Simulator or Device Hub (depending on Xcode) and runs two XCTest cases:

1. Settings categories, Quick setup opening/closing, model/recognition/OCR/download pages, voice-language search and a voice detail page. Category rows are tapped on their trailing side, outside the title.
2. Voice/Text/Camera navigation, language-menu search, text retained across mode changes and a simulated Home/return, and opening/closing history.

Tests use synthetic English text. Launch arguments select English and suppress automatic model loading and the first-launch wizard **for the simulator process**. Quick setup is still opened through Settings. No weights are downloaded and no recording or translation is started. This is UI coverage, not inference or first-install onboarding acceptance.

## Repeated runs and results

```sh
# Reuse a previously built simulator app; it may not include newer source changes.
python3 scripts/simulator/run.py --skip-build

# Run without opening the Simulator window.
python3 scripts/simulator/run.py --headless
```

The app build is in `.build/SimulatorDerivedData`. The generated, simulator-only test project is in `.build/KatSimulatorUITests`; each run has a timestamped directory under `runs/`, containing logs, `Navigation.xcresult`, a machine-readable result summary and exported screenshots. The command reports success only if both tests passed with no skips. Tests and results do not modify the checked-in Xcode projects or shipping app version.

For interactive use, select **Kat iPhone 17 Pro** in Simulator/Device Hub. For UI work on the owner's Mac, place Simulator on the built-in MacBook display; determine it from the current display layout rather than relying on a remembered display number. Do not overwrite system Accessibility permissions to work around an automation failure.

## Local models without a full second copy

Symlinked weight files are intentionally rejected by the package integrity checks. On APFS, seed independent copy-on-write clones instead:

```sh
python3 scripts/simulator/seed-models.py --whisper /absolute/path/to/turbo-q8_0.bin
python3 scripts/simulator/run.py --skip-build --model-check
```

The seeder verifies the existing Whisper Q8 digest and clones Index 9B/2B plus Denis and LJSpeech from the installed Mac model store. It never downloads data or replaces existing destination files, and fails if APFS cloning is unavailable. Only the dedicated booted iPhone 17 Pro simulator is allowed. Receipts are local copies; verification caches are rebuilt by Kat. Deleting or changing a simulator clone cannot change the original file. The seed occupies about 8.36 GB logically, while unchanged data blocks are shared with their sources; actual new physical allocation is not measured.

Simulator Whisper and Index use CPU because the current MTLSimDevice mapped-buffer path crashes. Rebuild the simulator TranslationRuntime with `bash scripts/build-translation.sh iphonesimulator` when preparing dependencies. Physical iPhone and Mac keep their existing GPU paths. The opt-in model check prepares recognition/translation and translates a short text; it is not a microphone or TTS quality test and is not a device-speed benchmark.

## Limits

The simulator uses the Mac's CPU, memory and graphics environment. Its timing, memory pressure and thermal behavior cannot be reported as iPhone measurements. Camera hardware is absent; entering/leaving the camera screen does not prove capture or OCR quality. Microphone routes, interruptions, phone background suspension, Live Activities and background download behavior still need physical-device acceptance. iPad, accessibility sizes and all locale layouts require additional explicit scenarios.

No App Store upload, device installation, model copying or cleanup is part of this command.

## Memory: one platform at a time

Quit native Kat and its model workers before booting the iPhone simulator. The runner refuses to start while they are running. After simulator tests, shut down the dedicated simulator before running Mac Kat or hosted Mac tests. On the development Mac, concurrent native Kat and simulator use exhausted memory; do not overlap inference or large builds across platforms. Duo stays installed but shut down.
