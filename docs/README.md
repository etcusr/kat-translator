# Documentation index

**English** | [Русский](README.ru.md)

- [Apple 1.1.0 local release preparation](publication/2026-10-22/README.md) — copy, gallery, artifacts and remaining gates.

Living documentation exists in two languages: `NAME.md` is English and is the default, `NAME.ru.md` is Russian. Both versions state the same facts and are updated together ([rule](GIT_WORKFLOW.md#documentation-languages)). Dated reports, benchmarks and research notes are evidence of a specific run; they stay in their original language and are not the current specification.

## Start here

| Document | Purpose |
|---|---|
| [README](../README.md) | Project overview, releases, quick links |
| [CURRENT_STATE](CURRENT_STATE.md) | Current releases, verified results, limitations and experiments |
| [Future work](BACKLOG.md) | Deferred product tasks and acceptance criteria |
| [ARCHITECTURE](ARCHITECTURE.md) | Code map, shared and platform layers, build commands |
| [Publication queue](publication/OPEN_QUESTIONS.md) | What remains before App Store / Google Play publication |
| [Project description](../PROJECT_DESCRIPTION.md) | Product description and identifiers |

[iPhone Simulator checks](../scripts/simulator/README.md) — repeatable settings and navigation tests without a physical phone.

## Platforms

| Document | Purpose |
|---|---|
| [Mac](macos/README.md) | Mac App Store and direct builds, packaging, testing notes, build history |
| [Android app](../apps/android/README.md) · [Android install and build](android/INSTALL.md) · [Android architecture](android/README.md) | Android release, build and porting history |
| [Platform layout](android/PLATFORM_LAYOUT.md) | Directory map shared by all platforms |
| [Android package storage](android/PACKAGE-STORAGE.md) · [Android media runtime](android/MEDIA.md) | Technical references |
| [OPUS Big](IMPLEMENTATION-opus-big.md) | OPUS engine and direction packages |
| [Shared model store](../model-store/README.md) | Local cache of weights for development |

## Rules and licensing

| Document | Purpose |
|---|---|
| [Licensing](LICENSING.md) | GPL-3.0-or-later for Kat's code; third-party terms; source kit |
| [Repository privacy](REPOSITORY_PRIVACY.md) | What may and may not be committed |
| [Git workflow](GIT_WORKFLOW.md) | Commits, releases, public history, documentation languages |
| [Contributing](../CONTRIBUTING.md) | How to propose changes and report bugs |
| [Branding](branding/README.md) · [Processing animations](branding/loading-animations/README.md) | Icon, theme, animations |

## Dated evidence (original language)

- `publication/*-2026-10-*.md` — store builds, privacy, licensing and runtime acceptance reports. Key ones: [Mac App Store builds](publication/macos-appstore-build-2026-10-14.md), [runtime acceptance 50/69](publication/runtime-acceptance-2026-10-14.md), [model download privacy](publication/model-download-privacy-2026-10-14.md), [localizations](publication/2026-10-14/LOCALIZATIONS.md).
- `licensing/2026-10-*/` — license reviews, notices and dependency source kit.
- `benchmarks/`, `android/benchmarks/` — measurements and device runs.
- `research/`, `android/ASR-OPTIONS.md`, `android/OCR-OPTIONS.md` — research and decision records.
- `maintenance/` — cleanup, migration, signing and source audits. Latest: [project cleanup, 21 October](maintenance/cleanup-2026-10-21.md).
- Historical implementation logs: [IMPLEMENTATION](IMPLEMENTATION.md) (RU), [startup verification cache](IMPLEMENTATION-startup-verification-cache.md) (RU), [language downloads](IMPLEMENTATION-language-downloads.md) (EN), [device testing protocol](../DEVICE_TESTING.md) (RU), [Android feature parity](android/FEATURE_PARITY.md) (EN), [Android interface parity](android/IOS_INTERFACE_PARITY.md) (EN), `macos/2026-10-10-shortcuts.md`, `macos/diagnostics/`, `branding/round-*`, `history/`.
