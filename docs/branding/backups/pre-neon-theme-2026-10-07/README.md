# Backup before the neon theme — 7 October 2026

`styles-before.zip` holds 63 source/resource files as they were immediately before the palette changes. SHA-256 values are in `manifest.json`; every archived file was checked after writing. No model weights, signing credentials or personal data are included.

For a targeted rollback, run from the project root:

```sh
git apply --reverse --check docs/branding/backups/pre-neon-theme-2026-10-07/neon-theme-only.patch
git apply --reverse docs/branding/backups/pre-neon-theme-2026-10-07/neon-theme-only.patch
```

The patch reverses only the theme changes, preserving the new recognizer setting and startup hint fix. Run the second command only if the first succeeds. If later edits conflict, restore individual styling changes from the archive after comparison; do not overwrite whole current source files blindly. Rebuild and reinstall after rollback.
