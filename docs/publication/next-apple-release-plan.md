# Next Apple release: presentation and publication plan

**English** | [Русский](next-apple-release-plan.ru.md)

**Progress, 23 October:** [local 1.1.0 preparation](2026-10-22/README.md): iOS archive/export, direct Mac packages, four-language copy, 28 iPhone screenshots and 12 full Mac window screenshots and 4 Quick setup previews, README/site gallery. No upload or review action. Mac Store 79 export now passes with a separate no-TLS Python runtime. Voice presentation scenes are ready in four languages. The target declares iPhone only; native iPad captures are outside this candidate. The owner-requested simulator demo is recorded and embedded locally; owner review/publication, Android captures and candidate upgrade acceptance remain open. Keep the checklist below incomplete until its full criteria are met.

Requested on 22 October 2026. **Planned work, not completed publication.** The current task does not upload builds, change App Store Connect or submit a review. Choose the new public versions when preparing the release; increasing only the build number is not a new public version.

## 1. Freeze the release scope

- [ ] Review changes since the last published iOS and macOS versions separately. Include only features and fixes actually shipped on each platform; label experimental features honestly.
- [ ] Update the repository documentation and product descriptions wherever behavior, supported features or limitations have changed. Keep English/Russian living documentation consistent and review store copy in EN/RU/ES/TR.
- [ ] Select new marketing versions for iOS/macOS and unique build numbers; record the exact source commit and validated artifacts.

## 2. Refresh screenshots for every platform and language

- [ ] Capture the final interface on iOS/iPadOS, macOS and Android in all supported interface languages: English, Russian, Spanish and Turkish. Cover translation modes, Settings/Quick setup and Models and voices where available on that platform; do not imply unreleased parity.
- [ ] Use consistent, representative examples and clean UI states. Exclude personal data, device identifiers, debug overlays and private recordings. Verify long labels, actual language, translation content and platform-specific layout.
- [ ] Retain selected source screenshots and optimized presentation assets in a clearly indexed repository directory by platform/language. Record capture version and generation/editing steps. Avoid redundant large binaries.
- [ ] Present a compact, attractive screenshot gallery on the GitHub repository front page (both README languages), with links to the full platform/language sets. Add the same approved assets to the GitHub-based project website.

## 3. Prepare App Store Connect

- [ ] Replace iOS/macOS screenshots for each store localization and required device size, using the validated release UI.
- [ ] Review descriptions and other metadata; update only where necessary and preserve deliberate keyword/title decisions unless separately revised.
- [ ] Write concise general release notes for the new update, localized in EN/RU/ES/TR, with platform-specific differences where needed. Match the final shipped changes; do not describe planned work as released.
- [ ] Create/select the new iOS/macOS public versions and upload their tested builds. Wait for processing, verify the selected build numbers, screenshots, metadata and release notes in each version.
- [ ] Check an in-place upgrade preserves existing models, voices, settings and history. Keep upload, review submission and public release as separate recorded steps; submit/release when authorized.

## 4. Record a short iOS demonstration

- [x] At the owner’s revised request, record navigation and actual translation in the simulator. The 33.5 s montage, poster and EN/RU/ES/TR captions are ready locally. [Checks](ios-demo-2026-10-23.md).
- [ ] Use non-private sample text/audio. Keep actual app behavior and timing clear; label any cuts or accelerated sequences rather than implying instantaneous processing.
- [ ] Export a compact web-compatible video with a poster image and short captions. Publish on the GitHub-based website and link/embed an appropriate preview from the repository README; keep the source/hosting location documented.

## 5. Redesign the project landing page

- [ ] Redesign the GitHub Pages home page with a more distinctive composition, the Kat logo, and the app’s dark/charcoal and lime palette.
- [ ] Show current screenshots of real translation workflows and a short playable video demonstrating navigation and core functions; connect this with the demonstration in section 4.
- [ ] Keep download links, source code, support and privacy easy to find. Check mobile and desktop layout, contrast, loading size and all supported page languages.
- [ ] Acceptance: approved visual preview with logo, screenshots and playable video, no private content, no misleading speed claims, and explicit authorization before publishing. Local preview implemented on 23 October: logo, dark/lime palette, EN/RU/ES/TR, switchable screenshots and responsive layouts. The owner accepted the overall design; the video is ready locally; its approval and publication remain open. [Checks](landing-preview-2026-10-23.md).

## Completion evidence

The release record should link the screenshot matrix/gallery, updated descriptions and release notes, source commit, uploaded build identifiers and processing/selection status. Video publication is a separate follow-up and must not be marked complete merely because screenshots or builds are ready.
