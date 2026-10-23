# Apple 1.1.0 — local release preparation

**English** | [Русский](README.ru.md)

Prepared 22–23 October 2026. **Not uploaded, submitted or published.** The existing Mac review is untouched. Public version 1.1.0 is proposed for both Store apps; the direct Mac candidate is 0.7.0.

| Candidate | Local result | Installed app |
|---|---|---|
| iOS 1.1.0 (73) | Release archive and App Store export passed | iPhone remains 1.0.1 (72) |
| Mac direct 0.7.0 (68) | Release build/native preview checks; signed DMG and ZIP prepared | Mac remains 0.6.9 (67) |
| Mac Store 1.1.0 (79) | Archive/export passed; separate no-TLS Python runtime, signed PKG ready | Existing Store submission unchanged |

**23 October capture update:** four prepared Voice scenes were added, rendered by real UI in an isolated simulator-only source snapshot. Four tests passed, no failures/skips. These are not inference or hardware acceptance. The normal simulator app was restored afterwards. [Method and scope](../ios-presentation-scenes-2026-10-23.md).

## Materials

- [Metadata and release notes](ios/en/whats-new.txt): `ios/` and `macos/`, each with EN/RU/ES/TR. Descriptions explain the consolidated settings. Names, subtitles, keywords and promotional text are unchanged from the 14 October source package; no assumption is made about later external edits.
- [Validation](metadata-validation.json): eight localized sets / 72 fields and two review notes. Validation of local copy is not validation or synchronization of App Store Connect.
- [Screenshot manifest](../../../site/assets/screenshots/2026-10-22/manifest.json): 28 iPhone 17 Pro simulator screenshots (1206 × 2622), seven screens per language; the four Voice scenes use prepared presentation state; 12 full Mac window screenshots (1440 × 900: Voice, Text and language picker over Image), plus four Quick setup native previews (1000 × 800). Pixels are unedited. Quick setup previews are excluded from Store assets. [New capture evidence](../mac-window-captures-2026-10-23.md).
- [Interactive gallery source](../../../site/screenshots/index.html) and [website](../../../site/index.html). Run `python3 -m http.server 8765 --bind 127.0.0.1 --directory site` from the repository and open `/screenshots/`. The site and README now show selected actual iOS captures; the website is now published (see the update below).
- [Release manifest](release.json), [Python packaging fix](../mac-store-python-2026-10-23.md), [capture procedure](captures.md).

Local, ignored binary paths: `dist/store/ios-1.1.0-73-final/OfflineTranslator.ipa`, `dist/macos/Kat-translator-0.7.0-build68-mac-arm64.{dmg,zip}`. SHA-256 sums and binary build identities are retained with the local artifact manifest. Models and signing material are not included in Git.

## Validation and remaining work

Four localized iOS UI capture tests passed without skips; short translations were produced by the seeded Index 2B CPU runtime. The original Mac native-view export test passed; three previews per language are now replaced by full-window UI captures, with actual Index translation and imported neutral audio. The fourth Quick setup preview remains. The gallery's eight platform/language selections were checked in the browser. These are presentation checks, not live microphone, Core ML, Metal or background-download acceptance.

Run **one platform at a time**: quit native Kat before booting the simulator, shut down the simulator before Mac tests. The simulator runner enforces the first condition. Concurrent runs exhausted memory on the development Mac. Duo remains installed and shut down.

Before uploading: finish Android captures; the current iOS target and exported IPA declare iPhone only, so native iPad captures are outside this candidate; validate final candidate upgrades on devices and recheck the final copy/build selection. The physical iPhone/Mac update retention evidence currently applies to builds 72/67, not these candidates. No fresh compatibility build for macOS 15–26 was made. Upload, processing, review and public release remain separate, unperformed steps.

Final local checks: iOS archive/export, app/widget 1.1.0 (73), no XCTest in IPA, both candidate app signatures; Mac package audit of 83 Mach-O files with no unresolved/external non-system dependencies. Metadata 8/72/2, docs parity 2, Store archive regression 5, simulator memory guard 2 and Mac project profiles passed. Default-sandbox signing/profile probes could not read certificate trust; reruns with system certificate access passed. [Artifact sizes, SHA-256 and build identities](artifacts.json). The ignored ready-to-copy folder is `dist/store/apple-1.1.0-preparation-2026-10-23-selected/`.

Mac Store 79: 142-Mach-O bundle audit, strict signature and installer certificate chain passed. Packaged Index MLX MTP2, OPUS Metal and Wayu frontend smoke passed; the helper-only smoke does not establish Store-sandbox or upgrade acceptance. iOS 73/direct Mac 68 predate the latest language layout fix and must be regenerated before claiming it. Store PKG: `dist/store/macos-1.1.0-79/Kat translator.pkg`. No upload or review change.

**Website published 23 October:** the approved design, gallery and funk demonstration are live on GitHub Pages; sound is initially muted. [Checks and remaining work](../website-published-2026-10-23.md). Website publication does not upload or release applications.
