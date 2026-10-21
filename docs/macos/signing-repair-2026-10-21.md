# Mac signing continuity — 21 October 2026

## Confirmed cause

The installed direct app, 0.6.8 (61), source identity `mac-207575e16807ad2b`, had a valid **ad-hoc** signature with no Team ID. Its designated requirement contained only the executable's code hash. The retained direct-release ZIP used an Apple Development certificate and a certificate-based requirement. These were different code identities despite the same app name, path and bundle ID.

The direct Xcode generator hard-coded `CODE_SIGN_IDENTITY = -` for both Debug and Release. The packaging script already selected a certificate, but installing a raw local Xcode product bypassed that protection. The installed bundle also contained hosted XCTest components and test-only entitlements. A successful deep signature check alone had not established signing continuity.

Apple documents how [designated requirements identify code across updates](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). The old certificate-signed release and the repaired copy now have equal designated requirements. This establishes identity continuity; it does not independently prove that every existing TCC entry grants access.

## Change

- `scripts/mac-signing.py` supplies the same selection policy to the direct project generator and package script. An available installed certificate wins over other certificates. A missing installed key, no usable certificate, or ambiguous initial choice fails explicitly. A fingerprint or exact certificate name can be supplied through `KAT_MAC_SIGNING_IDENTITY`; `-` is reserved for disposable builds.
- The tracked Xcode project reads its identity from ignored `.build/macos-signing.xcconfig`; no machine-specific certificate data is committed. Regenerate before building a fresh checkout. The regenerated project also reflects the already-current iOS extension version in its unused inherited objects; no iOS source/version change was made.
- Mac App Store generation keeps its existing automatic signing configuration and does not require the direct identity.
- The installed app was staged, stripped of XCTest components, signed with the retained release's original certificate and production entitlements, then replaced in place and launched normally. No TCC database edits or permission resets were performed. No app container was deleted.

## Fresh validation

| Check | Result |
|---|---|
| Original generator regression | Failed as expected: explicit identity was ignored and the generated setting remained `-` |
| Signing selection / generated-project tests | 8 passed, including Store isolation |
| Build-profile / bilingual documentation checks | 3 + 2 passed |
| Packaging shell syntax / Git whitespace | Passed |
| Xcode resolved Release settings | Correct certificate, manual signing, unchanged direct bundle ID and production entitlements |
| Automatic identity resolution after installation | Selected the original certificate without an override |
| Bundle dependency / entitlement audit | 161 Mach-O files; no external non-system paths or deployment-limit violations; production audio-input entitlement only, no XCTest bundles |
| Installed signature | Deep/strict verification passed; explicit evaluation against the retained release's requirement passed |
| Executable / resources | Executable payload identical after excluding the signature and its `__LINKEDIT` allocation size; only executable signature and resource seal changed, plus 13 removed XCTest files/links |
| Data before/after replacement | All 2,122 entries, 18,670,059,955 bytes, identical before ordinary launch |
| Data after ordinary launch | Same paths and contents; 423 JSON files changed formatting only |
| Models / history / preferences | All 1,647 model/package entries byte-identical; all saved preference values unchanged; all 20 history files preserved (one JSON formatting-only change) |
| Launch | Installed app running from `/Applications/Kat translator.app`, still 0.6.8 (61) / `mac-207575e16807ad2b` |

No new full compilation, recognition/translation benchmark or App Store upload was performed. Existing distribution packages were not regenerated. No Android source or device changes were made. Temporary staging/rollback app copies are removed after successful installation validation; the existing signed release ZIP is retained.

Screen-capture permission acceptance still requires the normal in-app action. Restoring the prior certificate can reuse a matching grant. If a stale entry still denies access, remove only Kat's old Screen Recording entry and add the current `/Applications/Kat translator.app`, then restart Kat; do not reset all privacy permissions. The screenshots' “Device Control and Data Access” toggle alone is not an acceptance check for the requested Screen Recording operation.

Signature/trust validation was run against the host keychain; a sandboxed attempt could not resolve certificate trust. Full host validation passed. Local private audit: `.build/mac-signing-2026-10-21/`; it is excluded from Git and contains no new model copies.
