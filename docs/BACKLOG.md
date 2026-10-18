# Future work

**English** | [Русский](BACKLOG.ru.md)

Deferred tasks, not completed changes or release promises.

## Image translation: completeness, layout and speed

Recorded 18 October 2026. **Deferred at the owner's request; no implementation started.**

The supplied Mac screenshots show two separate posts translated from Russian to English with Index-Translate 9B / MLX + MTP2. Some source lines are absent from the translated text; sentences become disconnected fragments. The right pane has excessive gaps and includes repeated channel headings and service metadata. In the exported image, some original lines remain untranslated, source text shows through overlays, and text sizes and coverage are inconsistent. The exact stage causing each omission is not yet established.

The displayed timings are OCR **33.17 s**, translation **12.14 s**, total **45.31 s**. These are observations from the owner's screenshot, not a new controlled benchmark.

Future investigation and acceptance:

- Trace OCR coverage, reading order, paragraph grouping, translation and export separately; establish where lines disappear.
- Preserve complete sentences and context inside each post while keeping independent posts separate. Handle quoted snippets, headings and service metadata deliberately.
- Make the text pane readable with consistent paragraph spacing; fit translated overlays without clipping, overlap or visible source text beneath them.
- Compare recognition and translation latency on the same inputs and settings without sacrificing text coverage or translation quality.
- Recheck the supplied source, exported image and interface together, plus additional multi-post and multi-column examples. Check all platforms' relevant image paths before claiming a cross-platform fix.

Earlier paragraph-layout checks remain evidence for their tested inputs; they do not establish quality on this new example. Private screenshots are retained locally outside Git; implementation is not part of the current iOS volume release.
