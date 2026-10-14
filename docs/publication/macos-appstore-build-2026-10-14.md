# Mac App Store: сборки 1.0 (61–63) — 14 октября 2026

## Решение

Отдельный магазинный вариант Mac собирается скриптом `scripts/archive-macos-appstore.sh` из того же сгенерированного проекта `apps/macos/KatTranslatorMac.xcodeproj`. Настройки магазина передаются только аргументами `xcodebuild`, поэтому обычная прямая сборка (`org.openoffline.translator.mac`, `KatMac.entitlements`, без sandbox, `package-macos.sh`) не изменена.

| Параметр | Магазинная сборка |
|---|---|
| Bundle ID | `app.kattranslator` — общий с iOS: одна запись App Store Connect для iOS и macOS |
| Версия / build | **1.0 / 63** (актуальная; 61 — с OpenSSL, 61 и 62 — с неработающим OPUS GPU) — совпадает с версией macOS-страницы ASC «1.0», иначе сборка не появится в поле «Build». Номер build продолжает Mac-последовательность после 60 |
| Entitlements | `apps/macos/KatMacStore.entitlements`: app-sandbox, device.audio-input, files.user-selected.read-write, network.client |
| Helper | `Contents/MacOS/OpusPython` (PyTorch Metal worker старого OPUS EN-пакета) подписывается `KatMacHelper.entitlements`: app-sandbox + inherit |
| Подпись | Archive — Apple Development (automatic), экспорт `app-store-connect` — Apple Distribution и 3rd Party Mac Developer Installer, профиль «Mac Team Store Provisioning Profile: app.kattranslator» (Xcode managed) |
| Info.plist | Копия исходного с версией 1.0/61 и `KatBuildProfile=mac-app-store`, создаётся в ignored `.build/macos-appstore/<версия>-<build>/` |

Команда: `KAT_MAC_STORE_BUILD=61 scripts/archive-macos-appstore.sh export|upload`. Team ID берётся из ignored `apps/ios/Config/Signing.local.xcconfig` или `KAT_APPLE_TEAM_ID`.

## Изменения кода

- `scripts/bundle-macos-runtimes.py`: при `ENABLE_APP_SANDBOX=YES` helper `OpusPython` и `torch/bin/torch_shm_manager` подписываются с наследованием sandbox, `protoc` не копируется. Для прямой сборки поведение прежнее.
- `shared/apple/Conversation/AppModel.swift`: импорт аудиофайла открывает security-scoped доступ на время чтения (в sandbox URL из file importer; вне sandbox вызов ничего не меняет).
- Скрипт проверяет: нет `.xctest`, строгая подпись, sandbox у приложения, inherit у helper, нет других исполняемых Mach-O.

## Проверки

- **Повторный upload 1.0 (61) после исправления: `Upload succeeded`** (xcodebuild, 14.10). Обработку сборки Apple и её появление в поле «Build» отсюда не проверял; в ASC ничего не менялось, «Add for Review» не нажималось.
- Первый upload отклонён серверной проверкой Apple: «App sandbox not enabled» для трёх файлов `Resources/OpusPython/torch/bin/*`. Исправлено исключением этих инструментов; build 61 не был принят сервером.
- Локальный экспорт до исправления: pkg подписан installer-сертификатом команды; в приложении `codesign --verify --deep --strict` PASS, все 161 Mach-O подписаны Apple Distribution, xctest нет, версия 1.0/61, ID `app.kattranslator`.
- Короткий запуск archive-копии (development-подпись, sandbox): процесс стартует, система включила AppSandbox, создан контейнер `~/Library/Containers/app.kattranslator`, падений нет. Это только запуск.
- Не проверено в sandbox: скачивание моделей, Index MLX 9B/2B, OPUS GPU worker, CT2, ASR/микрофон, TTS, OCR области экрана, выбор/экспорт файлов, горячие клавиши и перевод выделенного текста через Accessibility. Магазинная сборка начинает с пустого контейнера: модели и настройки прямой сборки не переносятся.

## 1.0 (62): без OpenSSL и других TLS-библиотек

По примеру iOS (`docs/publication/ios-openssl-removal-2026-10-14.md`) магазинная Mac-сборка больше не содержит криптографических библиотек. Причина та же: для OpenSSL при распространении во Франции Apple требует французскую декларацию по шифрованию.

В build61 были `_ssl`/`_hashlib` (Homebrew Python) с `libssl.3`/`libcrypto.3`, а также `hf_xet` (Rust, rustls) в окружении Index MLX. При `ENABLE_APP_SANDBOX=YES` `bundle-macos-runtimes.py` их не упаковывает. Встроенные `_md5`/`_sha1`/`_sha256`/`_sha512`/`_sha3`/`_blake2` сохранены, `hashlib` работает. Прямая сборка не изменена.

`mlx_lm` при импорте тянет `huggingface_hub` → `httpcore` → `import ssl`, хотя модель грузится локально (`HF_HUB_OFFLINE=1`). Поэтому `index_mlx.py` при отсутствии `_ssl` регистрирует инертный модуль `ssl`. Любая попытка создать TLS-контекст вызывает ошибку. При наличии настоящего `ssl` ничего не меняется. OPUS-стек (torch/transformers/sacremoses) импортируется без `ssl` и без заглушки.

Проверено на этом Mac, с Python-окружением без `_ssl`/`_hashlib` и Index без `hf_xet`, вне sandbox, на установленных моделях:
- Index 9B MLX MTP2 загрузился, нативные ядра активны, RU→EN: «The weather is nice today; let's go for a walk in the park.»;
- OPUS GPU worker (Metal FP16) EN→RU: «Алло, как ты сегодня?»;
- `ssl`/`_ssl`/`hf_xet` в `sys.modules` не загружались (кроме заглушки).

Проверено в pkg 1.0 (62):
- нет `_ssl`, `_hashlib`, `libssl`, `libcrypto`, `hf_xet`, `torch/bin`;
- поиск маркеров OpenSSL/rustls/BoringSSL по всем Mach-O пуст;
- все 153 Mach-O подписаны Apple Distribution, строгая проверка PASS.

Короткий запуск archive-копии 62 в sandbox — без падений. **Upload 1.0 (62): `Upload succeeded`** (14.10). В ASC ничего не менялось.

Скрипт `archive-macos-appstore.sh` останавливает сборку при появлении этих маркеров. Перевод внутри самого sandbox-приложения на моделях не запускался: контейнер пуст.

Ответ на вопрос о шифровании (export compliance) для macOS пользователь выбирает в ASC сам. Сетевые загрузки используют системный HTTPS (URLSession), он входит в исключение Apple для стандартного шифрования ОС.

## 1.0 (63): исправление OPUS GPU и проверка внутри sandbox

В 61 и 62 из `torch/bin` удалялся и `torch_shm_manager`. Однако `import torch` проверяет наличие этого файла (`torch/__init__.py`, `_manager_path`), поэтому OPUS GPU worker (старый пакет EN↔RU/UK/BE) падал с ошибкой `RuntimeError: Unable to find torch_shm_manager`. Ранняя проверка вне sandbox шла на окружении прямой сборки, где файл был, и ошибку не показала. Теперь файл сохраняется и подписывается app-sandbox + inherit; удаляется только `protoc`. Скрипт проверяет наличие inherit у обоих helper-файлов.

Проверка внутри sandbox. Та же store-конфигурация (sandbox, без OpenSSL/rustls, ID `app.kattranslator`, development-подпись), тесты `MacRuntimeTests` выполняются в процессе sandbox-приложения. Защищённый контейнер нельзя заполнить снаружи, поэтому тестовая подпись (не магазинная) добавляла только read-only исключение для `~/Library/Application Support/OfflineTranslator/` и `model-store/research/` с уже скачанными моделями.

| Тест | Результат |
|---|---|
| `MacMLXIntegrationTests` — Index 9B MLX MTP2 in-process | PASS: перевод, отмена до/во время, переполнение буфера, повторное использование, маршрутизация |
| `OpusGPUIntegrationTests` — helper в sandbox, Metal FP16 | после исправления PASS: EN→RU/UK/BE, RU/UK/BE→EN, отмена, повторное использование, роутер. До исправления FAIL (см. выше) |
| `CompactModelsIntegrationTests` | PASS: тест устройства CPU/Metal, Index 2B (llama.cpp Metal) RU→EN, OPUS CT2 RU→DE и DE→RU |
| `testRealDownloadInstallsIntoAppStorage` (новый opt-in, `KAT_REAL_DOWNLOAD_TEST=1`) | PASS: настоящая фоновая загрузка URLSession 12,6 МБ, SHA-256, установка в контейнер, удаление |
| `testImageOCRAndInvalidImport` | PASS |
| `MacIntegrationTests` (16) и `testImageImportAndTranslation` | 13 + 1 FAIL: тесты рассчитаны на установленные модели и пройденную настройку, а контейнер пуст («Download a translation model from Models first»); не прошедшие 3 — без моделей. Запуск этих же тестов на прямой сборке для сравнения не удался: «test runner hung before establishing connection» (дважды) |

**Upload 1.0 (63): `Upload succeeded`** (14.10); перед загрузкой скрипт подтвердил inherit у обоих helper-файлов и отсутствие OpenSSL/rustls.

Не проверено в sandbox: микрофон и голосовой путь ASR/TTS, снимок области экрана, горячие клавиши, Accessibility-перевод выделения, NSOpen/SavePanel вживую, первичная настройка через UI.

## Открыто

- Функциональная приёмка sandbox-сборки (лучше через TestFlight для macOS).
- Перевод выделенного текста использует Accessibility и синтетический Cmd+C; в sandbox это может не работать и вызвать вопросы ревью. Есть запасные пути: буфер обмена и меню «Службы».
- Лицензии: eSpeak (GPL) и модели — открытый вопрос из `OPEN_QUESTIONS.md`, сборку не блокировал.
- dSYM для Python-расширений отсутствуют: upload выдаёт предупреждения символов, не ошибки.
- Export compliance, App Privacy для macOS и отправка на ревью не выполнялись.
