# Apple settings navigation — 22 October 2026

## Scope

Implement the approved settings/model-management backlog on iPhone and Mac. Android remains planned. The owner explicitly requested subcategories and Apple Settings as the visual/navigation reference.

## Design

The Settings root starts with **Quick setup**, opening the original language/recommended-package wizard directly. It sits beside Models and voices in the same group. The other categories are grouped below: Recording, Interface, Memory, History, Experimental and About; macOS additionally has Keyboard Shortcuts. Use native navigation titles, back navigation, grouped rows, SF Symbols, consistent spacing and Kat's existing accent. Avoid one long page of unrelated controls.

Models and Voices contains Translation, Speech Recognition, Text Recognition/OCR, Voices and Samples, and Downloads. Translation selection stays alongside translation downloads; recognition selection stays with recognition downloads. The downloads page retains cellular consent and batch progress/pause/cancel. The setup wizard is on the Settings root rather than buried in Downloads. Voices are searchable by language and remain selected/downloaded through the existing coordinator. OCR uses native Apple Vision by default; iOS retains its existing optional OCR controls and packages; Mac describes its built-in route rather than offering unused packages.

Remove the separate top-level Models toolbar button. Missing-package hints, language-picker voice links, camera settings and the downloads URL open the appropriate Settings subcategory. Keep a usable back path to the Models and Voices hub and Settings root. iOS uses a NavigationStack; Mac uses the same hierarchy in its resizable settings sheet/window, with native grouped forms.

## Boundaries

No model ID/path/hash migration, downloader replacement, automatic deletion, language/voice/default changes, ASR/translation algorithm changes or Store submission. Keep current cancellation confirmation and current-batch-only deletion. Existing preferences, history and in-progress/resumable downloads belong to shared app objects, not the navigation view lifetime. Keep privacy/license information accessible. Preserve concurrent Android edits.

## Implementation

- [x] Split SettingsView sections into destinations; introduce shared category rows/surface and deterministic routing for package hints.
- [x] Split ModelsView into embedded translation/recognition/download categories, add shared OCR category, and give voice languages their own navigable list.
- [x] Redirect toolbar/hints/camera/language/setup entry points to Settings; localize new labels in RU/EN/ES/TR.
- [x] Check root/back/direct navigation and category coverage, build both platforms, update over installed apps, compare saved data/preferences and click the actual interfaces without large downloads.
- [x] Update bilingual current state/architecture/backlog, handoffs and validation report; create scoped local commits. No push/Store.

## Validation priorities

Opening/closing nested pages must not cancel downloads or change saved choices. Recognition and OCR hints must land on their own packages. Voice language searches must not change the selected voice. Long translations/accessibility text and compact window sizes must preserve back/close controls. Retention changes apply on settings dismissal as before, not when moving between categories. Destructive actions retain confirmation. Device checks distinguish navigation from actual network-transfer acceptance.

Validation results and remaining device coverage: [report](../publication/apple-settings-2026-10-22.md). iOS menu rows use full-width hit areas, including empty trailing space.
