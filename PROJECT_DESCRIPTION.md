# Kat translator

**English** | [Русский](PROJECT_DESCRIPTION.ru.md)

Working title: **Kat translator**.

**Short description:** Offline AI translator.

Kat translator translates speech, typed text and text in images on iPhone, Apple Silicon Mac and ARM64 Android devices. Choose your languages, download the models and translate without an internet connection.

- Voice input, audio import and text translation; phone cameras and image files, photo library or clipboard where supported.
- On-device speech recognition, translation and speech output for supported languages.
- Language search, favourites and quick direction switching.
- Text copying, translation history and sharing of generated audio.
- A choice of models and voices, with voice previews.
- Package downloads with progress, pause and resume support.
- Russian, English, Spanish and Turkish interface languages.

Speech, text, photos and translations are processed on your device and are not sent to the developer. Internet access is needed to download models and voices; download servers receive technical connection data. History is stored locally and can be disabled or cleared.

Recognition, translation, speech output and camera support depend on the language, selected model and device. Models may require several gigabytes of storage. Translations can contain errors, including numbers, names and times. Check important information against the original.

## Project metadata

Current releases, platform differences and verification limits: [CURRENT_STATE](docs/CURRENT_STATE.md). This product description is not a claim of complete feature or language parity across platforms.

This document is included in the Xcode navigator under **Kat translator — Project Info**. The App Store Connect record exists for iOS and macOS; localized store copy lives in `docs/publication/2026-10-14/`. Nothing has been submitted for App Review yet.

- Display name: `Kat translator` (same in RU and EN).
- iOS project/scheme: `OfflineTranslator`; macOS: `KatTranslatorMac`; Android: Gradle `app`/`inference`.
- iOS bundle identifier: `app.kattranslator` (selected on 2026-10-14; extension `app.kattranslator.downloads`; the installed legacy app still uses `org.openoffline.translator.prototype` and requires a separate data migration). The Mac App Store build uses the same `app.kattranslator`; the direct Mac build uses `org.openoffline.translator.mac`. Android application ID: `org.openoffline.translator.android`.
- Visual direction and logo candidates: [Brand notes](docs/branding/README.md).
- Current implementation, download dependencies and verification: [current state](docs/CURRENT_STATE.md), [download notes](docs/IMPLEMENTATION-language-downloads.md).
