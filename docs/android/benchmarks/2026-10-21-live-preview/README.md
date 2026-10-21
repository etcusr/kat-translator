# Android live phrase preview and progressive translation — 21 October 2026

Device: Pixel (Tensor G-series, Mali GPU), development debug build. Commits `d706241`, `8e5455c`.

## Why

On the owner's recordings the Pixel waited about 27 s for Whisper large-v3-turbo Q8 recognition of a 35.7 s
recording plus about 15 s for Index 2B (Vulkan) translation, all after the recording stopped.

- Whisper encodes every 30-second window in about 10.4 s on the Pixel CPU (2 windows for 35.7 s),
  regardless of phrase length, so it cannot follow speech phrase by phrase.
- Reducing `audio_ctx` (encoder 10.4 → 2.5–3 s) is **not quality-safe**: on 9 private history recordings it
  duplicated sentences (ctx 750, m64, m128) and changed words; even ctx 1000 changed text. Rejected.
- Fast recognizers already in the catalog, run with the same native code on the same 9 recordings:
  GigaAM v3 int8 0.33–0.77 s per 5–11 s clip and 3.0 s for 35.7 s; Parakeet v3 int8 0.5–1.8 s and 3.8–4.3 s.
  GigaAM meaning was close to Whisper but without punctuation/capitals and with numbers as words; Parakeet is
  punctuated but made more word errors. Private transcripts are kept outside Git.

## Changes

1. **Progressive Index output.** Android MTP adapter publishes text after every token (`kat_mtp_partial`), the
   non-MTP path uses shared `ot_mt_partial`; JNI `partial` trims to whole UTF-8 characters. `IndexEngine.partial()`
   is valid only while a translation runs. `PartialPoller` reads it every 120 ms on the main thread. The full-screen
   processing overlay is replaced by a bottom bar (status + Cancel) once text appears; text and voice workspaces.
   A failed or cancelled translation clears streamed text. Single-part status is «Перевожу» without «1/1».
2. **Live phrase preview for GigaAM** (previously Whisper only; Parakeet was briefly enabled in `8e5455c` and excluded in `f3ba723` after the owner judged its quality unacceptable). GigaAM output has no punctuation, so
   its phrase boundary is the existing one second of silence; the phrase becomes a sentence (capital letter,
   final period) before translation. The phrase translation grows during recording. With
   «Проверять текст после записи» off, only the unprocessed tail is recognized after stop.

## Checks

- `scripts/android/build.sh`: unit tests (new `RecordingPreviewTest` case), lint, debug and androidTest APKs: pass.
- Text, EN→RU, 148 characters, Index 2B Vulkan: partial text visible after about 3 s with the bottom bar,
  final text identical to the completed output, 5.43 s translation.
- Voice, RU→EN, GigaAM, verification off, synthetic Milena speech from Mac speakers (three sentences with
  2.5 s pauses): source and translation appeared during recording; after stop the remaining work was **0.18 s**.
  A single-phrase run without preview took 0.25 s recognition + 2.82 s translation.
- The owner's settings (Whisper Q8, verification default, silence 4 s) were restored after the test.

## Speech from the first finished sentence (`622a519`)

`SentenceFeed` hands finished sentences of the growing Index output to the voice thread, which synthesizes and plays
them while translation continues (Piper family and Supertonic; OmniVoice/Wayu keep the old path; not in memory-saving
mode). Pieces concatenate to the final translation; cancellation or failure stops playback. Streamed speech starts
after 2 s of audio instead of 4 s. Pixel, Text EN→RU, 198 characters, Index 2B Vulkan, Supertonic voice: first audio
about **5.4 s** after tapping Translate, while translation took 8.1 s; previously speech began only after the whole
translation and then the whole-text synthesis. Supertonic first reloaded its model for every sentence (about 0.7 s each); `02f43cf` keeps it in the shared speech
cache (`supertonicCreate`/`supertonicRun`), and synthesis of the same text finished at 13.1 s instead of 15.5 s.
It generates more slowly beside Index; pauses between sentences are possible. The «Озвучка» timing now includes
time spent waiting for sentences.

## Google on-device recognizer

`PlatformSpeechFileProbe` (opt-in androidTest) on the 35.7 s private recording, Russian, FILE input: 36.1 s, i.e. real time.
The first words were lost and several game terms and numbers were wrong where GigaAM was close to Whisper. Usable only
as a live streaming source, not as a quality improvement for Russian on this sample; other languages not measured.

## Russian live default, dates and times, English Parakeet v2

- `f7f0aba`: Russian live phrases use GigaAM when installed (owner's decision), whatever recognizer is selected,
  unless the preference forces Whisper or system recognition; verification still uses the selected recognizer.
- Eight synthetic Russian date/time phrases (macOS Milena, 16 kHz): GigaAM and Whisper Q8 recognized all words.
  Index 2B on GigaAM's spelled-out text broke two that Whisper's digits translated correctly («до двадцати одного часа» →
  10:01 PM, «восемнадцатого декабря» → "eighteenth day of the month"). Both inputs failed «в половине восьмого» (8:30)
  and «без четверти девять» (9:45 / 9:15). Index 9B translated all 16 inputs correctly but took 10–14 s per phrase vs 3–6 s.
- `RussianSpokenNumbers` (applied to every GigaAM transcript) writes dates, years, clock times and hour counts as
  digits («23 марта», «2027 года», «7:45», «до 21 часа», «21-го» without a month). With it Index 2B translated the
  previously broken phrases correctly; the two clock idioms remain 2B errors, as with Whisper.
- English: 60 LibriSpeech test-clean utterances (first part of the archive, 2 per chapter), Pixel CPU 4 threads.
  Parakeet TDT 0.6B v2 int8 and Whisper large-v3-turbo Q8 both 1.42% WER (19 errors / 1335 words; 5 better each);
  compute 64.7 s vs 1429.8 s. Read audiobook speech only; not integrated.

## Limits

- GigaAM loses question intonation: «У вас есть номер с видом на море?» became a statement. Speaker-to-mic test
  audio also produced one recognition error at the end («у реки» → «юрикей»). Not a quality evaluation.
- With Whisper selected, preview still costs at least about 10 s per phrase and lags behind speech; with
  verification on, the full recording is recognized again after stop.
- Speech starts after recording stops (from the first translated sentence of the remaining work). Timing rows show only the post-stop work.
- No real microphone session by the owner yet; two synthetic test entries were added to the Pixel history.
