# Git: saving changes and releases

**English** | [Русский](GIT_WORKFLOW.ru.md)

- After a finished change and an appropriate check, create a separate local commit with a short description of the result. Do not accumulate several releases in an uncommitted tree.
- Keep fixes, features and documentation updates separate when they are independent. State the check performed and its limits in the description.
- For a release, use a message with platform, version and build number, for example `release(ios): 0.5.6 (36) — …`. The commit itself does not mean installation or publication.
- Keep a mixed historical state as a snapshot; do not invent intermediate versions. The 12 October 2026 snapshot includes the accumulated move to apps/shared, Android, Apple and documentation.
- Before `git add`, check the file list, sizes, secrets, models and artifacts. Repeat the check after staging. Keep sources, catalogs/lock files, small shipped resources and test evidence.
- Do not commit downloaded weights, dist, vendor/build outputs, local signing settings or user imports. `.gitignore` does not delete files from disk and does not automatically untrack files that are already tracked.
- Do not use reset/clean or rewrite history to save space without a separate instruction. Ignored weights and builds are not protected by Git; they need a separate backup.
- Push/publication happens only on a corresponding instruction; a local commit is not an external backup.

## Public history

Work from the root of the current project: `main` → `origin/main` of the `etcusr/kat-translator` repository. The public history was restarted on 14.10.2026 with the `Initial source import` commit; earlier commits were not pushed to the new repository. The code is published under GPL-3.0-or-later. Do not add local backup archives of the old history to Git, do not merge old branches and do not run `push --mirror`. Save new changes as separate short commits. Publishing the sources does not grant permission for every later push.

## Public changes

Commit messages are written in English and briefly describe what was added, fixed or removed. Discussion history, internal instructions and assistant journals are not included in Git. Documentation describes the product, build, checks and limitations. Update CURRENT_STATE, ARCHITECTURE and the affected instructions when the implementation changes.

## Documentation languages

Living documentation is kept in two languages: `NAME.md` is English and is the default; `NAME.ru.md` is the Russian version. Both start with a language switcher and must state the same facts; update both in the same commit. Dated reports, benchmarks and research notes are historical evidence and stay in their original language. See the [documentation index](README.md).
