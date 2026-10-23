# Kat landing-page preview — 23 October 2026

Local-only redesign of the existing GitHub Pages source in `site/`; no deployment, push, App Store change or installed-app change.

## Presentation

- Existing Kat app icon reused unchanged as the logo; charcoal/lime palette and system fonts.
- EN/RU/ES/TR language selector updates headings, descriptions, image language, mode labels and page metadata.
- Voice, Text and Settings buttons switch the example image and explanation; larger Mac Text screenshot follows.
- App Store, other releases, repository, support, privacy and full-gallery links remain available.
- Upcoming-interface and prepared-Voice labels distinguish the pictures from the current Store version and inference evidence.
- Camera screenshots are excluded from iPhone presentation. The active gallery is 28 iPhone + 16 Mac entries; the selected Store folder contains 28 + 12.

## Checks

Browser: all 12 locale/mode combinations switched correctly; no horizontal overflow at the default desktop width or at 390 px. At 320 px, a decorative circle initially overflowed; the narrow-screen rule corrected it, with all four locales rechecked at 320 px. Russian desktop/mobile and Turkish narrow layout were visually inspected. No browser console errors were returned. Viewport override reset afterwards.

All four gallery locales show seven iPhone images and no camera entry. All 44 gallery assets and 40 selected Store screenshots match their recorded hashes; remaining screenshots were not edited. JavaScript syntax, Python compilation, documentation parity and simulator memory-guard checks passed (four Python tests). An independent source review found no important issues; it did not perform a screen-reader audit.

The live page uses no analytics, external fonts or new dependencies. It remains usable as an English static introduction without JavaScript; interactive modes and localization require JavaScript.

## Remaining work

This is a visual preview for approval, not completed release preparation. A real-device iOS demonstration is still unrecorded, so there is no video player or artificial substitute presented as a recording. Add the genuine compact video/poster after capture. Android screenshots, refreshed final Apple artifacts, candidate upgrade acceptance and separately authorized publication remain open in the release plan.

Local preview: serve `site/` over HTTP and open `/?language=ru` (or en/es/tr). Browser evidence is retained locally under `.build/landing-2026-10-23/` and is not a release screenshot.

## Native language-menu follow-up

The owner accepted the overall design and supplied a screenshot of unreadable native menu options. DOM inspection showed near-white inherited option text on a transparent option background, while the native popup used a white surface. Shared option rules now set dark text and an explicit white background/light scheme; the closed dark selectors retain their design. Browser-computed styles confirmed all four options use RGB(22,24,22) on white, and all four locale selections still work. Native popup pixels are excluded from the browser screenshot API on this host, so the visual popup check remains for the owner. This is a CSS change only, not a custom menu replacement or deployment.
