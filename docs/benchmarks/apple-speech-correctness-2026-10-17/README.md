# Apple streamed speech correctness — 17 October 2026

Subsequent verification: the corrected build was [installed and checked on iPhone](../iphone-speech-correctness-2026-10-17/README.md), using real playback plus independent control-audio recognition. The Mac-only checks below describe the earlier stage.

Follow-up to the [initial speech latency change](../ios-speed-2026-10-17/README.md). Four regressions were reproduced and corrected without changing translation generation settings or voice weights.

## Fixes

- **Long sentences:** the early-speech path formerly requested only the first `SpeechPreparation` fragment. It now drains every fragment, checks sample-rate consistency and retains all PCM before marking the sentence as spoken. This includes adaptive subdivision by the speech backend.
- **Whitespace:** the streamed queue retains the exact consumed translation prefix, including newlines, tabs and repeated spaces. The final remainder starts at that exact boundary; a change in formatting no longer triggers full replay.
- **Russian ordinals:** explicit endings remain supported; abbreviated `-й`, `-м`, `-е` use adjacent grammatical evidence for feminine oblique, instrumental/prepositional and plural forms. Verified examples include “на первой улице”, “перед первым рейсом”, “восьмидесятые годы” and “с пятнадцатого на шестнадцатое октября”. Unknown or adjective-separated contexts are preserved instead of forcing an incorrect form. A bare `-е` between 1 and 31 retains the existing day-of-month convention. This is a conservative rule set, not a complete Russian morphological parser; display text is unchanged.
- **Default Mac MLX:** the Python engine publishes cumulative decoded accepted tokens through a synchronous C callback to the Swift routed backend. The final returned translation remains authoritative. Callback state is invalidated before return so retained Python callbacks cannot access released Swift/request state. Cancellation, error recovery and reuse remain covered.

Two additional race regressions were fixed: a replaced prefix cannot start an obsolete sentence whose synthesis was pending, and cancellation while awaiting the previous playback cannot start the next sentence. Already-played audio cannot be retracted if a translation backend later replaces its generated text; the existing authoritative-final fallback still applies.

## Reproduction and verification

- Long-sentence and mixed-whitespace tests first failed on missing/repeated source words; both now pass. Two cancellation/rewrite race tests also failed before their fixes and pass afterward.
- Six ordinal tests initially produced 23 failed assertions; all pass after the fix, including dates and deliberately unresolved contexts.
- Complete OfflineCore suite: **288 executed, 2 opt-in skips, 0 failures**. The affected pipeline suite contains 82 passing tests.
- MLX Python/native bridge validation: **9 tests passed**, plus the existing error-lifetime probe. Five new regressions failed before adding the callback API. Final generation/token settings were not changed.
- **Mac Release app and test build passed; unsigned iOS Release build passed.** Mac tests use a separate development bundle identity and launch overrides disabling automatic model loading/history recording. The normal installed app and its preferences were not replaced. No iPhone installation, fresh microphone test or store publication was performed.
- Packaged Mac MLX integration passed with the installed Index 9B model: 20 partial snapshots, at least one genuine prefix before final completion, final output identical to the non-streaming call, callback-triggered cancellation and clean reuse. No callbacks survived request completion.
- Production `ConversationPipeline` + real `SherpaSpeechBackend`/Irina passed on a scripted synthetic translation containing a 90–180-character sentence, mixed whitespace and the ordinal examples. All source words were synthesized once in order; **4 synthesis fragments became 3 playback buffers**, **15.926 seconds at 22,050 Hz**, with finite non-silent PCM. Playback scheduling began before the scripted translation finished. The player captures scheduled PCM rather than recording speakers or microphone output.
- An independent local Whisper F16 run on that PCM, without a prompt, retained the complete word sequence. Comparison normalizes its conventional digit renderings (`1-й`, `15 на 16`, `80-е`) against the expanded spoken words. This supplements the input/PCM assertions; it is not a listening-panel pronunciation score.

The default routed MLX → real Irina complete-flow check also passed: 6 synthesis fragments, 6 playback buffers, each translated word synthesized once, and the first playback scheduled before translation completed. Together with the two checks above, all 3 fresh Mac integration tests passed. No fresh iPhone latency claim replaces the earlier 3.1-second observation; collecting a full sentence's speech fragments can slightly change first-audio timing.

## Running the checks

Run `swift test --package-path shared/packages/OfflineCore` and `python3 -m unittest discover -s scripts/validation -p 'test_*mlx*.py'`. Generate the Mac project and build its runtime-test target. Opt-in `MacMLXIntegrationTests` uses `KAT_MLX_INTEGRATION=1` and `KAT_MLX_MODEL_PATH`. `StreamedSpeechIntegrationTests` uses `KAT_STREAMED_SPEECH_INTEGRATION=1`, `KAT_IRINA_PATH`, and `KAT_STREAMED_SPEECH_OUTPUT`; its complete-flow test also requires the MLX variables. Keep artifact output in an ignored directory. Models, audio, local paths, device identifiers and raw logs are not checked into Git.
