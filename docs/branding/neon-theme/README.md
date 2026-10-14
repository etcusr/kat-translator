# Neon theme — Kat translator

Palette derived from the supplied neon cat icon: lime action color (`#C9FA33`), black background (`#000000`, restored at user request on 8 October), violet cards (`#1B1729`). Shared `KatTheme` in `Shared/CatProgressDrawing.swift` supplies app and download-widget colors. Errors and active recording retain semantic red/orange. Text remains white/secondary for legibility.

The new default vector cat uses a lime outline, pointed ears and a small face. Existing walking/running/jumping motion, scene suspension and Reduce Motion behaviour are reused; no movie or heavier model added. Previous four coats remain in source. `cat-walk.gif` is rendered directly from the production drawing and motion code.

Applied to conversation cards, language controls, recorder, download/preparation bars, settings, model/history/language screens, and Live Activity accents. The camera image remains unaltered. The supplied wizard video remains unchanged. The lock-screen cat uses progress updates; it is not a continuous walking animation.

Backup and checked theme-only rollback patch: `../backups/pre-neon-theme-2026-10-07/README.md`. Do not restore complete older source files over subsequent functional edits.

Validation: signed Release compiled; final app installed (.build/neon-final-install.log). Production-code cat preview inspected, four paws visually separated. 53 focused core tests and startup-hint lifecycle check passed, 478 localization entries validated. Earlier native picker UI checks failed; final explicit-row UI check could not start because device locked. This remains unverified on the physical screen.

8 October: language-pair tiles (shared by voice, text and camera), text editors/results and voice result/original cards use their backed-up neutral white-at-5%-opacity fill again. Lime tint is unchanged. Camera overlay backgrounds were already black and remain unchanged. Settings and privacy also restore their previous native grouped backgrounds and neutral card fills.
