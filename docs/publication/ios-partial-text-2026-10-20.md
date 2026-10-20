# iPhone progressive Index text — 20 October 2026

## Behavior

iOS **1.0.1 (57)** enables the existing Index 9B partial-output callbacks in Text and Voice. Translation text grows in its normal result card. A fixed progress/cancel row above the workspace replaces the blocking processing overlay for that request. The Text footer does not duplicate those controls; the keyboard closes and the first fragment triggers one scroll to the result. Later fragments do not repeatedly force scrolling.

The request keeps its presentation until completion/cancellation. Temporary text remains separate from final result/history fields. Cancel clears the partial; late callbacks are ignored. Existing recognition preparation and other nonpartial stages keep their previous presentation. OPUS and camera presentation are unchanged.

This enables visual display only: model files, MTP settings, token generation, translation chunk planning and speech streaming are unchanged. In particular, iOS does not adopt the Mac experimental 128-token chunk planner. The percentage counts completed source pieces, not generated output tokens, so the text can grow while the current piece still reports 0%.

## Verification

- Signed Release app and widget build passed; deep/strict signature verification passed. Both have version 1.0.1 (57).
- 102 focused OfflineCore tests passed, covering the conversation pipeline and Voice result visibility. Strengthened the partial-output tests with a real temporary history store: no history entry during a partial, one complete entry after success, and no entry after cancelling a displayed fragment.
- Standalone UI test on iPhone 17 Pro/iOS 27.0.1 passed against the installed production app and real Index 9B. A synthetic 490-character Russian travel paragraph produced visible English text while the inline cancel button remained active. The test captured the partial, cancelled it, checked the placeholder/removed partial notice, then translated again to a complete result.
- The device UI test covers **Text**; Voice presentation uses the same pipeline and is covered by unit tests. No new live-microphone acceptance is claimed.
- Test input/history handling: text-history recording was temporarily disabled through Settings and restored. All other persisted preferences compared equal. The previously absent `historyRecordText` key became explicit `true`, preserving its original default behavior; byte-for-byte preference equality is not claimed.
- 828 pre-existing entries under Models/VoicePackages retained size and modification time after the in-place update and UI test, excluding refreshed `.verified.json` receipts. This is metadata comparison, not a full weight SHA-256 run.
- 12 additional checks passed: Live Activity scheduler, bilingual documentation parity, build identity and release notices.
- Temporary test runner removed; ordinary Kat launch and final installed version 1.0.1 (57) confirmed.

The earlier Store 55 → development 56 retention/background test remains documented separately in [iPhone update acceptance](ios-update-acceptance-2026-10-20.md). Build 57 changes presentation, not background-download scheduling. No additional background transfer was repeated for this UI-only change. Neither development build was uploaded to the Store.

Private evidence remains under `.build/ios-update-2026-10-20/`: `partial-ui.xcresult`, exported UI attachments, `partial-core-tests.log`, `partial-app-build.log`, before/after preference snapshots and file inventories. These device outputs are excluded from Git.
