# Desktop diagnostics and panel surfaces

2026-10-08, macOS build 14 (`mac-3a9b0ee3c5125e51`).

History, Models (including detail panels), Settings and Diagnostics now use the native macOS window-background color rather than mixing black and grouped gray surfaces. The primary translation workspace remains black. The iOS resource layout and panel surface behavior are preserved.

Desktop diagnostics use separate Processor, Memory and Storage groups, 16-point label/value rows, 17-point headings and 14-point explanations. Labels are aligned left and values right; metric values are selectable and readable through accessibility. The measurements section is left-aligned and explains that its samples cover voice translations from the current app session, not text/image translations.

The collector still uses actual Mach task VM accounting, getrusage process CPU, host CPU ticks and volume capacity. Mac labels no longer say iPhone/iOS. The iOS per-app allocation-budget row is omitted on macOS, where that API is unavailable. Footprint, resident memory and viewing-session peak are identified explicitly; model file pages can contribute to resident memory without the same footprint charge. The metrics are not added together. Unknown recognizer IDs are displayed as such instead of being mislabeled Whisper; Meta Omnilingual has an explicit title.

Validation in `.build/desktop-diagnostics/`:

- Hosted resource sampling test passes: real CPU deltas in 0–100%, footprint/resident memory, viewing peak, physical RAM and disk capacities; unsupported Mac allocation budget stays nil.
- Mac UI test passes: opens Diagnostics, confirms Mac labels and live CPU percentage, then opens/closes Settings, Models and History. All four screenshots reviewed for consistent background and readable content.
- An initial UI test revealed the custom accessibility container omitted its value on macOS. Rows now expose both title and value in their spoken label; final UI test passes.
- iOS Release compatibility build passes. No phone installation was needed for this desktop change.
- Localization validation passes for 523 RU/EN entries.
- The packaged app passes the native dependency audit and signature check; installed app replaced with build 14 and normal launch checked. Previous installed build is retained at `.build/macos/previous-installed-before-build14.app`.
