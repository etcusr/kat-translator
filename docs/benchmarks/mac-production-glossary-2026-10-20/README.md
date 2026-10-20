# Optional automatic terminology glossary in the main Mac app

20 October 2026. Local Release development build 0.6.8 (61), Apple Silicon M3 Pro. Initial implementation validation did not replace Applications; the subsequent owner-requested installation is recorded below. No Store upload, submission or push.

## Behavior

Settings → Experimental → **Automatic terminology glossary** is off when no preference exists. Explicit choices persist in `macExperimentalTranslationGlossary`. RU/EN/ES/TR interface strings include the direction/model restriction, possible errors and extra startup delay.

Only **Index 9B MLX/MTP2, Russian → English** uses this option. Other directions and engines retain their usual path. The fast expanded `focused_terms` selector was ported from the frozen lab: repeated quoted expressions or nouns, observed inflections, at most ten terms, topic/local context and a short JSON translation prepass. The same resident model translates terms and the content. No manual glossary or additional weights are used.

Text and voice create a fresh document per completed input. OCR images pass the entire recognized source through `TranslationDocument` and routed/retained backends; all blocks share one document dictionary. Context-enabled image cache keys include the document identity, preventing reuse of another image's contextual translation. This does **not** maintain vocabulary across separate live conversation turns. The glossary preference is sampled at the first block and stays stable for that document; a supplied context cannot activate a disabled setting.

Matching entries augment the prompt both during token preflight and generation. Empty-prefix source-token counts stay unchanged. The normal chunk planning and output-budget retry behavior remain. Terms are soft instructions, not forced substitutions: consistency and correctness are not guaranteed.

CPU selection and the model prepass share cancellation with translation. No glossary JSON is sent to partial-text callbacks or history. Invalid JSON, missing dependencies or extraction context over 1,024 tokens produce an explicit localized error advising disabling the option; no silent plain fallback. If no terms repeat, the model prepass is skipped. A new request replaces the previous dictionary, and model unload releases it.

## Build inputs

Run `python3 scripts/prepare-mac-glossary.py` once before building the main Mac app. This build-time preparation downloads three pure-Python wheels with pinned versions and SHA-256 values in `shared/native/IndexMLX/glossary-dependencies.json`:

- pymorphy3 2.0.6;
- pymorphy3-dicts-ru 2.4.417150.4580142;
- DAWG2-Python 0.9.0.

The normal Mac runtime bundler verifies and copies the 64 prepared files (16,207,613 bytes) into IndexPython alongside `index_glossary.py`. It fails if preparation is missing; builds and the running app do not install packages implicitly. The running application needs neither the research environment nor a network package download. MIT notices and attribution/license links for the unmodified OpenCorpora CC BY-SA 3.0 dictionary data are included in ThirdPartyNotices.

## Verification

- Main Mac Release `build-for-testing`: passed. No marketing/build-number or model/catalog changes.
- OfflineCore: **343 tests, 3 skipped, zero failures**. New regression covers one document across OCR blocks, a fresh identity and uncached translation for a second image, disabled original overload, and retained-backend forwarding. Existing image progress/cancellation/cache tests also passed.
- Production glossary Python tests: **8 passed**. Real morphology matches the frozen lab selection; disabled path, matching aliases, source-token accounting, identical augmented preflight/generation prompts, document isolation, cancellation, empty candidates and explicit budget/JSON failures covered.
- Existing MLX/native bridge suite: **9 passed**, plus the executable error-lifetime regression. New C preparation cases cover success, failure, pre-cancellation and callbacks retained beyond a freed native flag.
- Hosted Mac tests: **5 executed, 1 unrelated opt-in residency test skipped, zero failures**. Fresh/default and saved preference; real packaged Index9B glossary on/off; exact ordinary output with supplied context while disabled; exact English→Russian output with the option on/off; genuine partials, cancellation during preparation, successful next request, full-image context through the routed/retained path; existing runtime limits/cancellation/streaming/Thai frontend coexistence.
- First hosted run had one test-harness failure: a launch argument forced the glossary off and overrode the isolated preference suite. Removing that argument resolved the test; the final complete hosted run passed. No production preference was modified.
- All **682** localization entries passed RU/EN/ES/TR coverage and placeholder/literal checks. Six notice tests passed; final package notice matches source exactly.
- Installed application executable and existing preference plist SHA-256 remained unchanged. Tests read already installed model weights; no new weight download or storage migration.

Final app deep/strict signature verification passed. All 64 packaged dependency files, both production Python modules and app notices match source/checksums; documentation parity passed both tests. Raw local logs and XCTest results stay outside Git. No manual Settings-click walkthrough, live microphone/OCR capture, macOS 15 machine run or App Store/TestFlight acceptance is claimed; the real runtime tests invoke the same production translation path with synthetic text and image-block context.

## Local timing and quality smoke comparison

One warmed request per setting on the existing synthetic `cooling` corpus document; this is a smoke check, not a new statistical quality benchmark. Full outputs are in [comparison.json](comparison.json).

| Mode | First visible text (includes heading) | First completed chunk | Full translation |
|---|---:|---:|---:|
| Glossary off | 0.69 s | 2.88 s | 10.36 s |
| Glossary on | 3.19 s | 5.25 s | 12.60 s |

Both outputs cover the input and retain the numerical readings, dates and warnings. The glossary version consistently uses “flow rate”; no broader quality conclusion follows from one document. The prepass still delays useful output. Earlier independent synthetic cases found mixed benefits and a terminology regression; [that report](../mac-glossary-corpus-2026-10-20/README.md) remains the relevant limitation. Semantic filtering, broader languages and default activation are deferred.

## Installed update

Later on 20 October, the verified product was installed at `/Applications/Kat translator.app`, preserving bundle identity `org.openoffline.translator.mac` and Application Support storage. Version remains **0.6.8 (61)**; source build identity is **mac-207575e16807ad2b**, implementing commit `7dd7d2a`. No rebuild or unrelated source changes were included.

The application was not running at replacement time. A local APFS copy-on-write backup of the data/preferences and the previous app was retained under the ignored installation evidence directory. The incoming app was staged and compared with the verified source product before replacement. All **25,248** app files matched, and deep/strict signature verification passed. Before launching, all app data and the preference file matched the saved state exactly.

A normal launch from the installed path succeeded and the process remained running after the data verification. Post-launch checks:

- **2,121** data files before and after; no additions or removals.
- **1,647** model files, including installed translation/recognition/voice packages, match SHA-256 exactly. No weights were downloaded or migrated.
- **20** history files preserve their contents; existing preferences are semantically identical, including the glossary remaining off.
- Of all data files, **1,679** remain byte-identical. The other **442** JSON files (440 download metadata, the transfer-state file and the history index) were reserialized at startup; parsed JSON is identical to the backup. This is not loss of history or model data.
- Finder's `.DS_Store` changed independently during backup verification. Only that metadata filename is excluded; models, history and preferences are included in the checks.

The updated app was left running for manual testing. This step verifies installation, ordinary launch and data retention, not a new live microphone/OCR or all-language acceptance run. The prior runtime tests above remain the functional evidence. Nothing was uploaded to App Store Connect.
