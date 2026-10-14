# Review notes · English

Draft for the release owner; insert reviewer contact in the store console. No login credentials are required by the reviewed application. Confirm this against the final release.

Kat translator performs translation locally. Model and voice data are downloaded separately over HTTPS. First use therefore requires a working network connection and enough free storage. After the required data packages are installed, recognition, translation and speech output are processed on the device. Model downloads are data packages; the final submission must not introduce downloaded executable code.

Suggested review path:
1. Select English and Russian and the compact OPUS translation model.
2. Download the required packages and prepare translation.
3. Open Text and enter: “Please do not add sugar. I need tea without sugar.” Translate to Russian and compare both sentences.
4. Open Voice, allow microphone access and record a short phrase. Stop recording to start the normal translation flow. Speech output requires its selected voice package.
5. Open Camera on iPhone/Android, or Image on Mac, and use a clearly printed, non-personal sample.
6. Enable History only if needed, open a saved test result and delete that entry when finished.
7. After downloading all necessary packages, disconnect the network and repeat Text and Voice.

OPUS supports English ↔ Russian/Ukrainian/Belarusian, not every pair among those four languages. Index provides a broader text language catalogue but requires several gigabytes of storage and substantial memory. Recognition, OCR and voices have different language coverage. Experimental recording preprocessing is disabled by default and is not necessary for review.

Mac-specific: the existing distribution is a standalone DMG/ZIP. These notes do not assert Mac App Store sandbox readiness. Review a separate store archive only after the release checklist is resolved.

## Кратко для команды

Ревьюеру нужен доступный сервер моделей, рабочий первоначальный сценарий и контакт издателя. Не обещать готовый перевод сразу после установки без скачивания. В форму отправлять точную версию/сборку, а не номера из этого исторического среза.
