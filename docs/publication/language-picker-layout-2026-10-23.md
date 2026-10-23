# Adaptive Apple language rows — 23 October 2026

Long localized names were squeezed between flags and three fixed-width capability/favorite controls, leaving individual letters on a second line. The shared iOS/macOS picker now measures the title and action group. Short rows stay inline; when necessary the title takes the full width and actions move below it. Controls keep their existing actions and accessibility identifiers, with one rendered set of controls. Selection, supported languages and downloaded models are unchanged.

Validation:

- Four iPhone 17 Pro simulator UI capture tests passed without failures/skips; 24 screenshots refreshed in EN/RU/ES/TR. The neutral directions sentence is translated by the real seeded Index 2B CPU runtime. Russian Azerbaijani names are visible intact. Full PNG inspection confirms controls and text remain in bounds in the sampled localized menus; reduced previews are not used as evidence of clipping.
- One native Mac preview test passed without failures/skips, rendering the actual language sheet at 560 × 640 in four locales. This is an NSHostingView export, not a whole desktop screenshot or a manual interaction test.
- Simulator and native Mac ran sequentially. The simulator was shut down before Mac testing; no physical iPhone installation or model download.
- The gallery retains 40 unedited PNGs (24 refreshed iOS captures + 16 earlier Mac settings previews), with SHA-256/dimensions in its manifest. The four extra Mac language-sheet renders remain local validation evidence.

Local evidence: `.build/KatSimulatorUITests/runs/20261023-030121/Navigation.xcresult`, `.build/language-mac-preview-2026-10-23.log`, `.build/language-mac-preview-2026-10-23/`. Test source: `PublicationPreviewTests.testLanguageMenuPreviews`.

The shared UI fix is included in the next Mac Store candidate. Previously exported iOS 73 and direct Mac 68 packages predate this fix and must be regenerated before claiming they include it. Simulator screenshots use the updated development source with the existing 73 version label. Installed apps and the existing Store review are untouched.
