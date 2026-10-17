# Preparing Kat for the App Store

**English** | [Русский](OPEN_QUESTIONS.ru.md)

**iOS 1.0 (53) and Mac App Store 1.0 (71)** were built from the corrected sources, verified and uploaded to App Store Connect. They include complete streamed speech, exact whitespace handling to avoid replay, contextual Russian ordinals and Mac MLX partial output. Both packages contain the current 13 loading clips. Project validation: 143 PASS. Apple processing, TestFlight installation and build selection for review are not yet confirmed. [Checks and upload result](apple-speech-store-2026-10-17.md).

**Earlier package update, 17 October:** iOS1.0(52) was verified and uploaded with microphone/memory-pressure fixes and 13 loading clips. TestFlight acceptance is pending. Mac70 is unchanged and still contains the removed clip. [Release report](ios-store-build52-2026-10-17.md).

The 14 October release was **iOS 1.0 (51), Mac 1.0 (70)**. It includes the playback fix, current privacy manifests and 46 license documents. [Build, checks and upload result](signed-sdks-release-2026-10-14.md).

## Done

- App Privacy and the RU/EN policy are published; the questionnaire is confirmed by the owner's screenshot.
- Three speech XCFrameworks are signed with Kat's certificate and the signatures are verified. 51 source files matched the official archives before and after signing. This is a distributor signature, not the upstream vendor's.
- The mapping of the embedded Sherpa/ONNX identifiers to release sources was checked. A wrong Sherpa commit was corrected and the exact archive added. 615 source inputs are verified. An independent byte-for-byte rebuild of all dependencies is not a required stage of this queue and is not claimed as done.
- The audio session fix was verified on iPhone: 6 tests and 2 repeated scenarios PASS; Mac player PASS. [Details](ios-playback-fix-2026-10-14.md).
- RU/EN/ES/TR materials are ready; listings and screenshots were filled in according to the owner's message, and the primary listing language is English (U.S.). No need to fill them in again. For macOS 1.0, build 66 was selected earlier; it needs to be replaced with 71.
- The free release, the Free Apps agreement and DSA non-trader status were confirmed by the owner earlier.

## Remaining for the release

1. **iOS53 and Mac71 were uploaded successfully.** Install iOS53 through TestFlight and run the full voice cycle. Upload does not establish TestFlight acceptance.
2. **The owner selects the new builds** on the iOS/Mac pages, checks Preview and the remaining required fields.
3. Check the iPhone microphone/permissions and the Mac system features through TestFlight; local checks do not replace this.
4. **The owner handles App Review.** The current iOS release is awaiting review according to the owner; replacing its build and resubmitting remain with the owner.

Separate radio-off, background download and network observation checks were dropped from the queue by the owner's decision; they do not count as passed.

## Kept licensing remarks

The [list](../licensing/2026-10-14/publication-and-sdk.md) keeps the questions about model terms, voices/media and GPL/App Store. Signing the SDKs does not close these questions, but they are not turned into an endless technical rebuild. Voices, models and media were not removed unilaterally. The separately rebuilt Opus remains an experimental candidate; release 51/70 uses the previously verified runtime.

## Next compatibility improvement

Discuss and verify iPhone 13 Pro as the lower bound for the light OPUS mode; this is a preliminary guideline, not a confirmed acceptance of that model. Separately, limit heavy models by available memory with a clear explanation. The exact bound and implementation are not approved yet; this remains separate from the uploaded 53/71 packages.
