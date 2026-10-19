# iPad and iPhone Duo screenshot requirements — 19 October 2026

## Decision

Additional iPad and iPhone Duo screenshot sets are not currently required for the inspected Kat iOS builds. No new images were generated or uploaded for RU, EN, ES or TR.

- **iPad:** the application declares only `UIDeviceFamily = [1]` (iPhone), not family 2 (native iPad). Applying Apple's device-family definition and screenshot requirements, a separate native iPad set is not required for this configuration. Compatibility-mode availability on iPad is a separate matter.
- **iPhone Duo:** Apple's published requirement starts in **April 2027**, for submissions using **iOS 27.1 SDK or later**. Kat already uses that SDK, but the requirement is not yet effective on the verification date. Revisit for submissions from April 2027; optional Duo images also advertise optimization for that device.
- The same device-size conclusion applies to all four listing languages. Existing iPhone listing assets are outside this check; their current server contents and visual accuracy were not revalidated.

## Fresh local checks

Read application Info.plist metadata directly from the retained archive and final IPA files; production sources, device-family configuration and binaries were not modified.

| Artifact | Version/build | UIDeviceFamily | SDK | Minimum OS |
|---|---|---|---|---|
| Retained Kat52.xcarchive | 1.0 (52) | [1] | iphoneos27.1 | 18.0 |
| Store IPA 53 | 1.0 (53) | [1] | iphoneos27.1 | 18.0 |
| Store IPA 54 | 1.0 (54) | [1] | iphoneos27.1 | 18.0 |
| Store IPA 55 | 1.0 (55) | [1] | iphoneos27.1 | 18.0 |

Build 55 is the latest locally documented successful upload. The supplied App Review message concerns build 52; the selected server build was not independently queried. The old 52 exported IPA was removed during earlier retention cleanup; its archive is the evidence inspected here.

## Separate App Review issue

The supplied review message reports that the widget did not appear in the system Widget Gallery on iPad Air 11-inch (M3), iPadOS 27.0, for version 1.0 (52). Empty store screenshot slots are not the reported bug. Apple's compatibility guidance explicitly permits iPhone apps to run on iPad and requires checking that experience. This task did not reproduce or fix the widget issue; build 55 is not claimed to resolve it.

## Sources checked

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) — required display sizes and the April 2027 Duo deadline.
- [Apple UIDeviceFamily definition](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html) — family 1 is iPhone/iPod touch, family 2 is iPad.
- [Apple compatible-device testing](https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices) — iPhone apps on iPad in compatibility mode, independent of native supported destinations.

No App Store Connect changes, uploads, new builds, device runs or screenshot resizing were performed. Device-family metadata checks and documentation validation do not establish App Review acceptance.
