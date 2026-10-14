# Android: interface parity with current iOS

User requirement, 2026-10-11: replace the engineering Index probe with the current iOS interface. Reference started with iOS 0.5.3 (32); the current Apple tree independently advanced to0.5.4 (33), adding Voice audio sharing. The older turquoise Open Offline screenshots are not the reference. This design is already selected by the user; no new design approval is needed.

Source of truth:
- shared/apple/Conversation/ConversationView.swift, TextTranslationFields.swift, LanguagePairPicker.swift
- shared/apple/Shared/CatProgressDrawing.swift (KatTheme)
- shared/apple/Audio/VoiceStageControls.swift, RecordButton.swift
- shared/apple/History/HistoryView.swift
- shared/apple/Models/ModelsView.swift
- shared/apple/Settings/SettingsView.swift

Required presentation: black background, #C9FA33 accent, compact title and history/settings/models toolbar, segmented Voice/Text/Camera selector, language cards and swap action, auto-speech row, vertically stacked text panels, footer Translate button, full-screen processing state with cancellation, grouped dark sheets. Android system bars, keyboard and system share/file picker remain native. No model weights or voice files are copied into app source folders.

Validation: instrumentation of modes, sheets, language selection, edit/copy/clear, cancellation, rotation/state restoration, history persistence and a real Index translation from the new text screen. Screenshots on Pixel 9 Pro for visual inspection. Existing native token/Unicode/model acceptance tests remain.

Runtime availability is separate from appearance: current Android runtime supports Index text translation. ASR, shared offline voices and OCR must remain visibly unavailable until their actual Android runtimes are integrated; decorative buttons must not imply successful recording or recognition.

Performance feedback: user reports 1.55 seconds for Index on iPhone (0.35 seconds was OPUS Big). Pixel CPU-only UI measurement was 19.4 seconds. This is not a controlled device comparison: repeat with identical model hash, input, prompt, context, warm state and timing boundaries before attributing the gap. GPU now runs through Vulkan, with the validated Mali narrow-projection workaround; warm short translations measured8.5 seconds. See benchmarks/2026-10-12-pixel9pro-index-vulkan.

Android0.2.1 follow-up: G715 single-token matvec selection reduces the same warm
phrase to7.29 seconds; iPhone parity remains unmet. Full profiling evidence and
different-length text results: benchmarks/2026-10-12-pixel9pro-index-profile.

Verified on Pixel: both Compose UI tests pass (navigation/languages/editing,
reader, history/settings/models, camera return, rotation, real Vulkan Index,
new persisted history ID). Screenshot evidence is in
benchmarks/2026-10-12-pixel9pro-index-vulkan/ui-*.png.

Remaining parity: ASR/TTS/OCR, English UI localization, favourite languages,
automatic model downloads, long-text segmentation, audio/image history and
complete advanced settings. The port must not be described as fully finished.
