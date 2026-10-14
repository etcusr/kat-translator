# Mac store packaging and Pages follow-up — 14 October 2026

Reviewed the code changes in `b976907` (`generate-macos-project.py`, `archive-macos-appstore.sh`) and subsequent status-only commits `513e12e` / `94ceb27`. No new working-tree edits were present when this review began.

The generated store project applies the store identifier, sandbox, Info.plist and testability settings to the app target. Hosted test targets keep their own identifiers. The script no longer passes these settings globally to SwiftPM resource targets. In the extracted PKG66, FluidAudio and OfflineCore resource bundles have distinct component identifiers, no application `NSServices` key and no separate `_CodeSignature`. Strict deep code-signature verification succeeds with normal keychain access. The restricted sandbox check initially reported `CSSMERR_TP_NOT_TRUSTED`; repeating with host trust access passed. Five archive failure-handling regression tests pass. No actionable regression was found in this reviewed change. This is a scoped review, not a new device/TestFlight acceptance or an audit of every older build helper.

## GitHub Pages

The screenshot corresponds to the first deployment, [run 38491850909](https://github.com/etcusr/kat-translator/actions/runs/38491850909), which failed while configuring a Pages site that was not yet available. The next run of the **same commit**, [38491945765](https://github.com/etcusr/kat-translator/actions/runs/38491945765), succeeded one minute later. The current Pages API configuration reports `build_type: workflow` and the expected public URL.

A fresh HTTPS fetch of [the privacy page](https://etcusr.github.io/kat-translator/privacy/) succeeds and its body is byte-identical to `site/privacy/index.html`. No workflow repair or rerun was needed. The Node 20 deprecation annotation is a warning, separate from the original missing-Pages error. No repository settings, workflow versions, deployments or remote content were changed in this check.
