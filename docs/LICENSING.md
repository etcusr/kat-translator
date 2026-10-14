# Kat translator license

**English** | [Русский](LICENSING.ru.md)

Kat's source code is published on GitHub under the **GNU GPL version 3 or later — `GPL-3.0-or-later`**. The full unmodified GPL v3 text is in [LICENSE](../LICENSE). Earlier commits and dated reports may still describe the former closed mode; this decision applies to the current source release.

Copyright (c) 2026 the respective copyright holders of Kat translator.

Kat translator is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Kat translator is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Scope

GPL-3.0-or-later applies to Kat's original code and to accompanying material owned by its copyright holders, unless a file carries a different applicable notice. Copyright is not transferred. The license also permits commercial use under the GPL; the author's plan to distribute the app for free does not add a non-commercial restriction for recipients.

The Kat license **does not relicense** third-party libraries, dictionaries, fonts, graphics, audio, models, datasets or voice weights. Their notices and terms are preserved. Sources are recorded in `assets/catalogs`, the dependency lock files and the [component audit](licensing/2026-10-12/README.md). Large downloadable model weights, installers, local signing material and user data are not part of the published Git repository. Bundled resources, including the compact language identification model and voice previews, keep their own terms and notices.

## eSpeak and binary distribution

The GPL path was chosen for Kat's own code, so the owner stopped the study of replacing eSpeak with VoiceGarden. eSpeak remains in the main runtime for now. The public repository is part of meeting the obligations; it does not by itself prove that any IPA/APK/DMG/PKG is ready for distribution.

A specific binary release must provide the complete corresponding source, including required modifications and dependency build instructions, preserve the notices and meet the applicable GPL conditions. Links to other people's repositories are not a universal fulfilment of every obligation. Store terms, signing/delivery and the absence of impermissible additional restrictions are checked separately before an App Store release. This is not closed yet.

Local development does not require publishing the whole working repository immediately. Opening the GitHub repository was a separate, explicit decision of the owner. Publishing the source does not include permission to submit the app to stores or to redistribute third-party weights with unclear rights.

## Voices and publication queue

**Denis and all other current voices stay.** The previously discussed removal was cancelled: no explicit prohibition was found, and Kat downloads the weights from a third-party server instead of storing them in its own Git. The rights uncertainty and third-party license terms are documented in the [primary confirmations](licensing/2026-10-14/denis-lessac.md) and the [review of all Piper packages](licensing/2026-10-14/voice-alternatives.md). The choice is revisited if an explicit restriction or a substantiated claim appears.

Opening Kat's code does not change those rights and does not lift the NC/OpenRAIL/attribution terms of other packages. The staged queue is in [OPEN_QUESTIONS](publication/OPEN_QUESTIONS.md). Public contact: katlabs.dev@gmail.com; the [privacy policy](https://etcusr.github.io/kat-translator/privacy/) and the support page are published separately. The legal publisher and user terms are agreed before a store release; the GitHub account name is not used in place of a legal name.

The review of the published history and its limits: [REPOSITORY_PRIVACY](REPOSITORY_PRIVACY.md).

Current review of the license kit: [contents of the final packages, fixes and specific open questions](licensing/2026-10-14/release-package-review.md). The sources contain 46 documents; the latest store packages IPA50/PKG69 contain 42. The new license documents and the audio fix will ship in the next release.

## Dependency source kit

605 archives and 9 frontend files were [collected and verified locally](licensing/2026-10-14/source-kit.md); URLs/SHA-256, submodules, patches and reproducible notices are included in the repository. The archives are stored outside Git; see [public delivery, SDK signatures and remaining questions](licensing/2026-10-14/publication-and-sdk.md). Having them does not replace an independent check of the complete corresponding source for the binaries actually shipped and of the distribution channel terms.
