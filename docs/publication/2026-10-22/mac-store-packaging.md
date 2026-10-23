# Mac Store packaging investigation — 22 October 2026

**Resolved on 23 October:** Store 1.1.0 (79) archived and exported with the separate no-TLS CPython runtime. See [resolution and validation](../mac-store-python-2026-10-23.md). The investigation below describes the earlier build 77 failure.

Candidate 1.1.0 (77) archives successfully but the existing no-bundled-TLS guard stops export. This is a confirmed change in the packaged Python runtime, not a false match in an unrelated document.

`mac-build-profile.py` now selects the pinned python-build-standalone 3.11.17 for every profile. `libpython3.11.dylib` exports `PyInit__ssl` and `PyInit__hashlib`; both the library and `Contents/MacOS/OpusPython` contain the OpenSSL version and initialization strings. `otool -L` lists system dependencies rather than a separately removable libssl. The library code is embedded. The existing Store bundler only removes `_ssl`/`_hashlib` extension files and separate crypto dylibs, so it cannot remove these built-ins.

Evidence: local `.build/release-2026-10-22/mac-store.log`; failed archive under `.build/macos-appstore/1.1.0-77/`. No Store export or upload was attempted after the guard failed. Existing review, installed app and encryption declarations were not changed.

Required next work: prepare a pinned, reproducible Mac Python runtime without the unused built-in SSL/hashlib implementations, validate Index/OPUS/voice imports and actual inference, and archive with a fresh build number. Alternatively any deliberate change to the packaging/compliance policy requires separate review of actual bundled functionality and accurate declarations. Do not simply weaken the grep guard, strip strings, hide symbols or falsely claim the runtime has no crypto. This report makes no legal determination about exemption eligibility.
