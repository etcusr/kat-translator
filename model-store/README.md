# Shared local model store

**English** | [Русский](README.ru.md)

`downloads/` is the single tree of downloaded models and voices for all platforms.
Existing content was moved without copying. `Dependencies/downloads` is a temporary
symbolic link to it for older vendor scripts.

Models are not placed in `apps/ios`, `apps/macos` or `apps/android` and are not part
of the APK. On a separate device the app keeps its own verified local copy: iOS and
Android sandboxes cannot use the computer's store directly.

Shared package descriptions and SHA-256 checksums live in `assets/catalogs/` and
`docs/android/portability-contract.json`. The format determines compatibility:
GGUF/ONNX are portable when the runtime supports the architecture; Core ML is for
Apple platforms; executable libraries are built separately for each OS/ABI.
