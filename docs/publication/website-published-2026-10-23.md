# Website publication — 23 October 2026

Published at https://etcusr.github.io/kat-translator/ after owner approval of the design and selection of the funk soundtrack.

- Source: `d81de6554b9f5c4fdf69736ebfffbe8e4882d67e`, pushed to `main` without rewriting history.
- [GitHub Pages deployment](https://github.com/etcusr/kat-translator/actions/runs/39887016558): completed successfully.
- Live homepage, landing JavaScript, screenshot manifest and selected MP4 fetched from the public URL are byte-identical to the local sources.
- Selected video SHA-256: `a9def134b1b3accd60eaab488d5175629493ff6fbb9d90cca7a2c745a3f5d49e` (1,328,461 bytes, 33.478 s).
- Live browser: playback starts muted, no subtitle tracks; EN/RU/ES/TR switching works. Manual sound enabling was checked in the same player locally before publication.
- Earlier local responsive/contrast/screenshot checks remain recorded in [landing preview](landing-preview-2026-10-23.md); the public deployment uses those same files.

The website and repository presentation are public; Apple builds are not uploaded or released by this operation. Prepared Voice screenshots are labelled as presentation examples; actual video translation is a simulator recording, accelerated 1.15×, not a physical-device benchmark. Alternative soundtrack previews remain in the repository; the homepage uses funk.

## Next work

1. Freeze final Apple release scope and review prepared descriptions/release notes against actual changes and the latest App Store Connect metadata (which may contain external edits).
2. Rebuild final candidates: iOS 73/direct Mac 68 predate the language-picker layout fix. Mac Store 79 exists with the no-TLS Python fix; verify final source alignment and Store-sandbox/upgrade behavior before upload. Refresh build numbers for any new upload. The proposed Store version is 1.1.0.
3. Check in-place candidate updates preserve models, voices, settings and history. Prior physical-device retention evidence applies to 72/67, not the new candidates. Keep native Mac and simulator runs separate.
4. Upload approved screenshots, descriptions, release notes and tested builds to App Store Connect when separately authorized. Keep upload, processing, review submission and public release distinct; existing Mac review was not changed or freshly queried here.
5. Android screenshots remain a separate open item for full platform coverage. A fresh macOS 15–26 compatibility build is not prepared.
