# Apple 1.1.0 — local release preparation

**English** | [Русский](README.ru.md)

Prepared 22–23 October 2026. **Not uploaded, submitted or published.** The existing Mac review is untouched. Public version 1.1.0 is proposed for both Store apps; the direct Mac candidate is 0.7.0.

| Candidate | Local result | Installed app |
|---|---|---|
| iOS 1.1.0 (73) | Release archive and App Store export passed | iPhone remains 1.0.1 (72) |
| Mac direct 0.7.0 (68) | Release build/native preview checks; signed DMG and ZIP prepared | Mac remains 0.6.9 (67) |
| Mac Store 1.1.0 (77) | Archive passed; packaging blocked by embedded OpenSSL in standalone Python | Existing Store submission unchanged |

## Materials

- [Metadata and release notes](ios/en/whats-new.txt): `ios/` and `macos/`, each with EN/RU/ES/TR. Descriptions explain the consolidated settings. Names, subtitles, keywords and promotional text are unchanged from the 14 October source package; no assumption is made about later external edits.
- [Validation](metadata-validation.json): eight localized sets / 72 fields and two review notes. Validation of local copy is not validation or synchronization of App Store Connect.
- [Screenshot manifest](../../../site/assets/screenshots/2026-10-22/manifest.json): 24 iPhone 17 Pro simulator screenshots (1206 × 2622), six screens per language; 16 native Mac view previews (1000 × 800), four per language. Pixels are unedited. The Mac previews are **not** final Store screenshots.
- [Interactive gallery source](../../../site/screenshots/index.html) and [website](../../../site/index.html). Run `python3 -m http.server 8765 --bind 127.0.0.1 --directory site` from the repository and open `/screenshots/`. The site and README now show selected actual iOS captures; publication requires a later push.
- [Release manifest](release.json), [packaging blocker](mac-store-packaging.md), [capture procedure](captures.md).

Local, ignored binary paths: `dist/store/ios-1.1.0-73-final/OfflineTranslator.ipa`, `dist/macos/Kat-translator-0.7.0-build68-mac-arm64.{dmg,zip}`. SHA-256 sums and binary build identities are retained with the local artifact manifest. Models and signing material are not included in Git.

## Validation and remaining work

Four localized iOS UI capture tests passed without skips; short translations were produced by the seeded Index 2B CPU runtime. One Mac native-view export test passed without skips (16 images). The gallery's eight platform/language selections were checked in the browser. These are presentation checks, not live microphone, Core ML, Metal or background-download acceptance.

Run **one platform at a time**: quit native Kat before booting the simulator, shut down the simulator before Mac tests. The simulator runner enforces the first condition. Concurrent runs exhausted memory on the development Mac. Duo remains installed and shut down.

Before uploading: resolve Mac Store Python packaging without bypassing its crypto guard; capture full Mac application screens at Store dimensions; finish Voice/Image and Android captures; assess iPad requirements (current iOS target is iPhone-only); record the real-device iOS demonstration; validate final candidate upgrades on devices and recheck the final copy/build selection. The physical iPhone/Mac update retention evidence currently applies to builds 72/67, not these candidates. No fresh compatibility build for macOS 15–26 was made. Upload, processing, review and public release remain separate, unperformed steps.

Final local checks: iOS archive/export, app/widget 1.1.0 (73), no XCTest in IPA, both candidate app signatures; Mac package audit of 83 Mach-O files with no unresolved/external non-system dependencies. Metadata 8/72/2, docs parity 2, Store archive regression 5, simulator memory guard 2 and Mac project profiles passed. Default-sandbox signing/profile probes could not read certificate trust; reruns with system certificate access passed. [Artifact sizes, SHA-256 and build identities](artifacts.json). The ignored ready-to-copy folder is `dist/store/apple-1.1.0-preparation/`.
