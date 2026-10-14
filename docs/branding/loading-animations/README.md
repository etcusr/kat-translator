# Processing animations

**English** | [Русский](README.ru.md)

## English cat-break caption — 14 October 2026

The `cat-break` clip and its poster now say **CAT BREAK** instead of the two Russian captions. The clip is shared by all iOS/macOS/Android languages; there is no language filter. H.264 384×288, 24 fps, 103 frames / 4.292 seconds, no audio. Black bars cover the former captions; the central area keeps the cat's motion.

`prepare-loading-animations.py` automatically applies `localize-cat-break.py` after normalizing this clip. The localizer uses ffmpeg and macOS AppKit (`render-cat-break-caption.swift`) for a reproducible text layer; the source must be 384×288. The poster is taken from the new video. The source SHA values in the catalog refer to the original clips; the transformation is marked by the `caption`/`captionLanguage` fields. Changing the caption does not change the origin of or rights to the source clip.

The current gallery and ZIP are updated; a separate GIF preview: `dist/share/loading-cat-break-en.gif`. Installed or previously downloaded apps get the replacement with the next build.

## Persistent gallery — 11 October 2026

Current set: 10 drawn-cat motions and 14 clips. On 14 October `one-beer` was removed from the resources of all platforms and from the generator; old signed packages remain historical artifacts. A puddle trick with a jump over it was added; "Pile" now ends with burying using the hind paws. Both scenarios are part of sequential playback. The bounce starts early and includes the push-off, tucking the paws and a soft landing. Three short body contractions are visible before the puddle; the burying is kept.

[Open the gallery](gallery/index.html). It contains **only the current** drawn-cat motions and app clips. The **"Play all"** button plays them in turn, shows the current number and stops on a second press. Individual cards can also be played and downloaded. The HTML works after unpacking the whole folder, without a server or internet.

**Rule for further work:** adding, changing or removing an animation is always accompanied by an update of this gallery. Historical exports in `dist/share/*-2026-10-11` remain snapshots; the maintained directory is `gallery/`.

```bash
python3 scripts/update-animation-gallery.py          # update the current gallery
python3 scripts/update-animation-gallery.py --zip    # also an archive to share with friends
python3 scripts/update-animation-gallery.py --check  # only check that it is up to date
```

The clip list comes from `assets/bundled/LoadingAnimations/loading-animations.json`; new entries get a card automatically, removed ones disappear from the HTML and the managed files. A `title` in the manifest entry sets the caption of a new clip. The cat export uses the current SwiftUI drawing, motion models, `CatLoadingPlay.Trick.allCases` and the shape from the app. New random tricks are exported automatically; if a trick needs a special start, the export stops explicitly until the scenario is updated instead of skipping it silently.

Changing the cat sources invalidates the export: the next run re-renders MP4/GIF/posters through SwiftUI and ffmpeg. With unchanged code the heavy export is not repeated. `--check` needs neither ffmpeg nor compilation. HTML/CSS/JS are generated from `scripts/update-animation-gallery.py` and `scripts/animation-gallery/`; files in `gallery/` are not edited by hand.

Preparing new clips updates the gallery automatically. The iOS/macOS project generators and Mac packaging check that it is current before writing the project or building the package. Synchronization deletes only files listed in its own `_generated.json`, keeping any other notes. Regressions for adding/removing/folder boundaries: `python3 scripts/validation/test_animation_gallery.py`.

Current archive for friends: `dist/share/Kat-loading-animations-current.zip`. It contains the whole folder with HTML and media; unpack it and open `index.html`. App clips are not re-encoded for the gallery.

## Processing clips — initial integration

The user supplied Telegram MP4 clips (15 originally, 14 after `one-beer` was removed on 14 October). Together with the existing wizard cat they form a shared local playlist for **only the former CatWizardView locations** in Voice/Text processing. Model-preparation and download-progress cats remain unchanged.

- Clips are shuffled without replacement; no consecutive repeat across shuffle cycles or separate waits in one app process.
- Clip selection survives SwiftUI body updates. From Mac 29 / iPhone 18, each clip plays once, then the playlist advances at its end. Short clips no longer repeat to fill 8 seconds. Completion/cancellation dismisses the animation immediately.
- One muted AVPlayer and one current item per visible surface; no audio-session changes. Playback pauses when the app is inactive or Reduce Motion is on; a poster remains visible. Dismantling removes the observer and player item.
- Bundled H.264, 384×288, aspect-fit with black padding, frame rate capped at 24 fps, all audio removed. Original source identities are kept in the manifest; raw source files are not distributed in the repository. Only the persistent letterbox on `giphy.mp4` is cropped, not subjects or captions.
- `scripts/prepare-loading-animations.py` reproduces the assets with ffmpeg/ffprobe. `assets/bundled/LoadingAnimations/loading-animations.json` records original names, SHA-256 hashes, output sizes and durations. Total video size at integration time: 1,628,520 bytes; JPEG posters are additional.

## Central processing overlay (Mac 29 / iPhone 18)

Voice recognition/audio import and text translation display one large animation in a shared overlay above the dimmed workspace. Width adapts to the available area, up to 640 pt, preserving the 4:3 canvas. Status, optional real part/character progress and a Cancel button of at least 44 pt remain visible. The underlying workspace is disabled and hidden from accessibility while processing. Cancellation uses the existing pipeline cancellation path; keyboard editing ends when the overlay appears.

The overlay ends when processing completes or speech starts, so automatic speech leaves results readable. It is not used for model preparation/downloads, Image, or ongoing microphone capture. Existing small speech-preparation indicators remain available. At the user's request, short clips play only once before the next clip is selected.

Validation: Mac native UI test passed (25.868 s), including the centered Cancel, cancellation, actual text editing afterwards, restart and the translated result. iPhone native UI test passed (50.381 s), including overlay sizing/cancel target, cancellation/restart and return to results. Mac automatic-playback visibility test passed (1.524 s). Final playlist tests: 4 passed, 0 failures (6.940 s), including real first-play advancement and native poster/video handoff. Screenshots on both devices were reviewed. Evidence: `.build/processing-overlay/`. The first Mac UI attempt failed on an unreliable NSTextView accessibility enabled flag; testing actual editing replaced that assertion and passed.

## Verification

Evidence is stored under `.build/loading-clips/`. The original contact sheets and the normalized poster sheet were visually inspected. `LoadingAnimationTests` checks the bundled media, shuffle fairness, real playback/end transitions, pause, dismissal cleanup and the native Mac video/poster handoff.

Validated releases: **Mac 28 / iPhone 17**, installed and launched normally on 9 October 2026.

- Mac: 4 targeted runtime tests, 0 failures, 12.206 s. Includes real native video rotation/poster visibility and decoder cleanup.
- iPhone: production text translation UI test, 0 failures, 43.555 s; successful translation, clearing and screenshots reviewed. This short UI check is not an exhaustive on-phone playlist test.
- Both bundles: all 15 clips of that time and their posters verified against the normalized assets; signatures passed.
- Mac DMG: checksum verified; the dependency audit found no external non-system libraries across 86 Mach-O files.
