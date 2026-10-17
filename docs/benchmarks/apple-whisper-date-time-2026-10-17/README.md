# Apple Whisper: separating spoken time and date — 2026-10-17

Follow-up: [optional correction and recognition preparation](../date-setting-capture-2026-10-18/README.md). The checks below describe the original source-validation stage.

## Change

Apple `WhisperBackend` keeps its normal large-v3-turbo F16/Metal greedy decoding. A Russian clip of at most 30 seconds with one plausible time/day triple separated by dots or hyphens immediately before a month name gets one additional acoustic decoding. Only that retry suppresses digit tokens, disables timestamps and caps output at 256 tokens. Disabling timestamps is necessary: suppressing digits while retaining timestamp decoding produced a repeated punctuation tail in the rejected experiment.

`WhisperDateTimeRepair` requires the retry to agree with the original surrounding words, hour, minute, ordinal day and month. Only punctuation/case/ё variation is ignored; zero-prefixed spoken minutes are supported. The accepted replacement is `H:MM, D month`, keeping the original surrounding text. Invalid times/calendar days, identifier contexts, multiple triples, changed words/numbers, incomplete output or repeated punctuation retain the original. The second pass shares cancellation and model ownership; its processing time is included in the ASR metric.

This is deliberately narrow: no general date guessing, no change to translation prompts, models, ordinary recognition or Android. More than 30 seconds, unsupported date order/forms and disagreements remain unchanged. Other numbers elsewhere can prevent strict agreement and therefore leave the ambiguous triple unrepaired; they are never overwritten from the retry.

## Fresh checks

- Original symptom reproduced with baseline greedy and beam search 5. A separate local Parakeet Ultra decoding and diagnostic spelled-number Whisper decoding agreed on the intended time-before-date reading. Private recording/transcripts are excluded from this report and Git.
- Actual Apple backend source was compiled in a local macOS harness against the existing production Whisper library and OfflineCore. One private exported recording plus eight synthetic Milena recordings were processed by baseline, fixed and repeated fixed backends, in one reused context per run.
- All three malformed triples (private recording, synthetic dotted triple and synthetic hyphenated triple) were corrected. Six unaffected controls remained **byte-identical to the baseline Apple backend**; all nine fixed texts were identical on repeat.
- Current Index 9B/llama runtime translated all three repaired results with the correct time and date. This was a local runtime check, not an iPhone UI/end-to-end playback check.
- Cancellation propagated during a subsequent transcription; model reuse after cancellation reproduced the corrected private result. The precise cancellation stage was not instrumented.
- Test-first checks failed before implementation (four initial assertions, then two assertions for discovered hyphen/leading-zero cases). OfflineCore: **295 tests, 2 opt-in skips, 0 failures**, including 7 new regression tests.
- Unsigned iOS Release build: **PASS**. No installation, version increment, distribution/store update or push.

Synthetic inputs are in `controls.json`; they are generated speech, not additional human recordings. This small set is not a general accuracy guarantee or a fresh iPhone performance measurement.

## Observed latency on Mac

Private clip: baseline 0.809 s; fixed 3.196 s on its first measured run and 2.603 s on repeat. Two synthetic ambiguous clips: baseline 0.792–0.793 s; fixed 2.243–2.458 s. Six ordinary controls: baseline 0.755–0.829 s; fixed 0.756–0.860 s. These are sequential observations, with no thermal/performance-isolation claim. The rare second decoding costs additional time; ordinary clips take the original single-pass path.

## Reproduction

Run `swift test --package-path shared/packages/OfflineCore`. The regression tests contain only invented text and cover valid time/day evidence, ordinary dates/amounts/codes, calendar limits, wrong language, changed numbers/words, hallucinated suffixes, repeated punctuation, date-first ambiguity and zero minutes. The local ignored `.build/date-time-asr-2026-10-17` holds the audio probe, synthetic audio, raw transcripts and compiler/runtime logs. Rebuild generated helpers if cleanup removed them. iOS compile check used the existing OfflineTranslator scheme with Release/iphoneos, generic iOS destination and `CODE_SIGNING_ALLOWED=NO`.
