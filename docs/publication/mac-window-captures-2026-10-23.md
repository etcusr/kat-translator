# Mac publication windows — 23 October 2026

Requested replacement order, in EN/RU/ES/TR:

1. Voice, with a completed original and translation.
2. Text, with a completed original and translation.
3. Language picker over Image, with diagnostics disabled.
4. Existing Quick setup native view preview (retained, clearly labelled, excluded from Store assets).

A temporary opt-in `MacUITests.testPublicationConversationWindows` used the actual app, an imported neutral synthetic Samantha audio fixture and the installed Index model. Audio is generated to a local file without speaker playback. It is **not a live microphone test**. The text example describes a train journey; the audio asks about a hotel reservation. The source and English-to-Russian translations are the same across interface localizations, making the comparison consistent. Actual result strings are retained in local XCTest JSON attachments; personal recordings are not used.

The test disables diagnostic UI through launch arguments, restores the clipboard, and terminates its separately built app. History flags supplied as string launch arguments did not suppress text archival: the current history reader expects typed Boolean defaults. Twelve exact synthetic records from capture attempts were removed afterward; all 52 unrelated records were preserved with their original serialized JSON objects. No model or audio files were removed. The temporary capture test is retained only in local evidence, not as an unsafe reusable committed test. Future runs must use typed settings or an isolated history store. Installed Mac/iPhone binaries are not replaced, the simulator stays shut down, and no Store action or push is performed. UI sources are shared with Store candidate 1.1.0 (79); the UI-test app still identifies as direct development 0.7.0 (68), so captures are not falsely labelled as screenshots of an installed Store package.

Capture method: `XCUIElement.screenshot()` of Kat's full window, 1440 × 900. No pixel editing, compositing, fake result fields or screenshots of unrelated windows. The collector preserves PNG bytes and records hashes/dimensions/method. Only the three explicitly replaced gallery images per language are removed; Quick setup and iOS captures remain.

Earlier capture attempts exposed test-harness issues: sandboxed runner cannot write directly into the repository (changed to XCTest attachments), and waiting for the import button after memory-saving unload is not a valid completion condition (changed to completed output and enabled mode switch). Those attempts are not acceptance. Final capture run passed: one test, all four locales, zero failures/skips, 12 window PNGs. Recognition and both translations were identical across locales. Representative Voice/Text/language frames were inspected visually; all 40 gallery images passed dimension/hash/size checks. Local evidence: `.build/publication-mac-2026-10-23/final.xcresult`, `capture-test.swift`, result JSON attachments and retention report.

Final retention check: all 2,133 prior paths/sizes retained, no added/removed files, all preference values restored (including two file-picker keys). The 52 retained history objects preserve their serialization; no whole-tree checksum claim is made. Browser checks confirmed the new order in all four Mac localizations. Gallery: 40 images, 6,683,160 bytes. The fresh ignored preparation folder contains 24 iPhone and 12 Mac screenshots, 72 text fields, two review notes and the release status; Quick setup previews are excluded.
