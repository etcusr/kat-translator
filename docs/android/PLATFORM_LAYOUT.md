# Platforms and shared resources

**English** | [Русский](PLATFORM_LAYOUT.ru.md)

The baseline was the latest working tree of 11.10.2026: iOS **0.5.3 (32)**,
Mac **0.5.4 (52)**, including the latest fixes to voice row identity and
screen-region translation languages. The Git branch was not reset.

| Directory | Purpose |
|---|---|
| `apps/ios` | iPhone entry point, camera, Live Activity, Xcode project, signing, UI tests |
| `apps/macos` | Mac entry point, windows/screen capture, Xcode project, Mac tests; the store variant is generated into the ignored `.build/macos-store-project` |
| `apps/android` | Gradle project, Android UI, JNI, on-device tests |
| `shared/apple` | SwiftUI, AppModel and integrations used by both Apple platforms |
| `shared/packages` | Shared Swift packages; nested C targets belong to their packages |
| `shared/native` | C/C++ runtime and platform C adapters |
| `assets/catalogs` | The single editable model catalog and detailed manifests |
| `assets/bundled` | Small shared resources, localization, voice previews, OCR dictionaries |
| `model-store` | Ignored models and voices, one copy per computer |
| `Dependencies` | Pinned vendor sources and build artifacts, separate per OS/ABI |
| `tests` | Shared benchmark fixtures and checks |

`models.json` holds the source IDs, URLs, sizes and SHA-256 values. The command
`python3 scripts/generate-model-catalog.py` generates the Swift adapter;
`--check` forbids drift. Android uses `assets/catalogs` directly through a
Gradle source set, without an editable copy of the catalog. `platforms` marks
file portability; runtime success is confirmed separately by a test on each OS.
Core ML packages are not included on Android.

Index is stored by digest in `model-store/blobs/sha256`; the old name in `downloads`
is a link. The import `scripts/models/blob_store.py` checks size and SHA,
creates a hardlink and atomically replaces the original name with a symlink: data
blocks are not copied. Other existing downloads stay in the shared `downloads`.
`Dependencies/downloads` temporarily points to the same tree for older tools.

Migration check: Python layout/catalog tests; 261 Swift tests, 2 pre-existing
skips; iOS and Mac Release `BUILD SUCCEEDED`. Sources/resources of both Xcode
build phases were compared with the original project; only the shared `models.json`
was added. Bundle IDs, versions and signing settings were kept. Apps on Apple
devices were not reinstalled. The source snapshot, membership and logs are in
`.build/platform-layout/{before,after}`. A build check does not replace a UI run.

Building from the repository root:

```bash
python3 scripts/generate-project.py
python3 scripts/generate-macos-project.py
swift test --package-path shared/packages/OfflineCore
xcodebuild -project apps/ios/OfflineTranslator.xcodeproj -scheme OfflineTranslator -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData build
xcodebuild -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/MacDerivedData build
```
