# Whole-image translation progress — 20 October 2026

The Mac image screen displayed each OCR block's local backend progress directly, then cleared it between requests. Consequently a multi-paragraph image repeatedly showed part 1 of 1 or 1 of 2 and reset its percentage. The supplied recording confirms that presentation problem; its article differs from the separately supplied quality-review screenshot.

ImageTranslationSession now publishes one scene-wide character total and counts OCR blocks as parts. Backend chunk progress contributes proportionally within the active block. Completed/cached blocks remain counted; retries cannot rewind the counter; the bar stays present between requests. Scene/request guards reject stale callbacks. Partial text remains separate from final/cache/export/history data. OCR grouping, prompts, model weights and translation chunking are unchanged.

## Validation

- The new regression test failed on the previous implementation with 10 assertions: absent global total, local part count, progress disappearing/resetting between requests, retry rewind and missing cached work.
- After the fix, all 340 OfflineCore tests passed (3 optional skips). Coverage includes partial lifecycle, cache, stale scene callbacks, timing and same-language behavior.
- Mac Release build-for-testing and 2 real OCR/Index integration tests passed. The private image reconstructed as 5 blocks (title plus 4 paragraphs), 2,574 source characters. All 18 progress events retained that total, never regressed and had no intervening empty progress. Final translation completed. The synthetic wrapped-sentence control retained a single paragraph and its numbers.
- Private-image recognition was 0.186 s and summed translation inference was 18.193 s in this run. These are stage timings, not end-to-end latency or an A/B speed comparison. All saved preferences were equal before and after the hosted tests.

## Quality assessment scope

Manual comparison used only the supplied image and pasted output, not an uncropped full article. Main paragraphs, figures and entities were broadly retained. Some terminology widened in meaning (an aerial raid became an offensive; drones became aircraft), and a colloquial reference to a military line remained too literal. The screenshot itself ends mid-word, so an absent continuation is not evidence of translator truncation. This is a fidelity review, not factual validation of the source's claims. No quality improvement or speedup is claimed by this progress-only fix. Private media and text are not included in Git.

## Installed build

Mac 0.6.8 (61), source ID `mac-17491f3ca1f33c1e`, was installed and opened normally. The candidate and previous installed build have the same designated signing requirement; strict/deep signature and 161-Mach-O bundle checks passed. All 2122 data files/links and preference values were preserved; the previous app remains in the local ignored rollback directory. Final ordinary build contains no test bundle. No Store upload, distribution package update or push. No new native UI automation or mobile-device check was run for this progress-only change; the real Mac test observed the published state consumed by the existing progress panel.
