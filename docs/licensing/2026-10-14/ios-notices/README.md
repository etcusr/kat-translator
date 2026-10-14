# Shared license texts collected for release preparation

These are unmodified license/notice files from the local pinned source inputs or the upstream URLs recorded in `manifest.json`. SHA-256 verifies the copied text, not permission for every file in the finished app. ONNX Runtime's upstream aggregate notice includes optional dependencies; its presence does not imply that all listed components are linked into Kat.

`python3 scripts/assemble-ios-notices.py` assembles these texts and Kat's GPL license into `assets/bundled/ThirdPartyNotices.txt`. The iOS project includes this resource. `--check` verifies original hashes and generated content. Line endings are normalized only in the assembled resource; the source files remain byte-for-byte copies. The macOS project has also been regenerated to include this shared resource; the iOS attribution set does not certify completeness for a Mac package.

The current set contains 38 files, including macOS supplements labeled in the assembled resource. Android now packages the shared resource too. Apple apps expose it offline under component licenses. Fresh checks and precise remaining gaps: [release package review](../release-package-review.md). Existing IPA47/PKG66 still contain the older set.

This is an attribution set, not a complete legal release sign-off. Remaining work:

- Match the prebuilt sherpa archive to all transitive source revisions and build options; provide complete corresponding source and the applicable build scripts, not only links to project homepages.
- Verify the remaining static/transitive code and dictionary provenance against the final binary. The inventory of seven local checkouts is not the entire dependency graph.
- Resolve distribution conditions for GPL components through App Store; retaining Kat's GPL license does not settle additional platform terms.
- Complete model/voice/preview attribution and apply any relevant NC/OpenRAIL conditions. Downloadable weights are separate from the app's source license. Existing voice decisions remain unchanged.
- Obtain rights evidence for the bundled third-party animations, or choose a release composition that does not include them. The media hashes in the source inventory identify the exact resources; their filenames are not licenses.

See [the release preparation report](../../../publication/ios-release-preflight-2026-10-14.md), [source inventory](../ios-source-inventory.json), and [binary inventory](../ios-1.0-build47-binaries.json).

Original upstream text bytes (including CRLF and trailing whitespace) are preserved with `.gitattributes`; the manifest hashes are checked against both working files and staged Git blobs. Only the assembled app notice normalizes line endings.
