# Mac App Store: первая сборка 1.0 (61) — 14 октября 2026

## Решение

Отдельный магазинный вариант Mac собирается скриптом `scripts/archive-macos-appstore.sh` из того же сгенерированного проекта `apps/macos/KatTranslatorMac.xcodeproj`. Настройки магазина передаются только аргументами `xcodebuild`, поэтому обычная прямая сборка (`org.openoffline.translator.mac`, `KatMac.entitlements`, без sandbox, `package-macos.sh`) не изменена.

| Параметр | Магазинная сборка |
|---|---|
| Bundle ID | `app.kattranslator` — общий с iOS: одна запись App Store Connect для iOS и macOS |
| Версия / build | **1.0 / 61** — совпадает с версией macOS-страницы ASC «1.0», иначе сборка не появится в поле «Build». Номер build продолжает Mac-последовательность после 60 |
| Entitlements | `apps/macos/KatMacStore.entitlements`: app-sandbox, device.audio-input, files.user-selected.read-write, network.client |
| Helper | `Contents/MacOS/OpusPython` (PyTorch Metal worker старого OPUS EN-пакета) подписывается `KatMacHelper.entitlements`: app-sandbox + inherit |
| Подпись | Archive — Apple Development (automatic), экспорт `app-store-connect` — Apple Distribution и 3rd Party Mac Developer Installer, профиль «Mac Team Store Provisioning Profile: app.kattranslator» (Xcode managed) |
| Info.plist | Копия исходного с версией 1.0/61 и `KatBuildProfile=mac-app-store`, создаётся в ignored `.build/macos-appstore/<версия>-<build>/` |

Команда: `KAT_MAC_STORE_BUILD=61 scripts/archive-macos-appstore.sh export|upload`. Team ID берётся из ignored `apps/ios/Config/Signing.local.xcconfig` или `KAT_APPLE_TEAM_ID`.

## Изменения кода

- `scripts/bundle-macos-runtimes.py`: при `ENABLE_APP_SANDBOX=YES` helper подписывается с наследованием sandbox, а `OpusPython/torch/bin` (protoc, torch_shm_manager) не копируется. Worker их не вызывает. Для прямой сборки поведение прежнее.
- `shared/apple/Conversation/AppModel.swift`: импорт аудиофайла открывает security-scoped доступ на время чтения (в sandbox URL из file importer; вне sandbox вызов ничего не меняет).
- Скрипт проверяет: нет `.xctest`, строгая подпись, sandbox у приложения, inherit у helper, нет других исполняемых Mach-O.

## Проверки

- **Повторный upload 1.0 (61) после исправления: `Upload succeeded`** (xcodebuild, 14.10). Обработку сборки Apple и её появление в поле «Build» отсюда не проверял; в ASC ничего не менялось, «Add for Review» не нажималось.
- Первый upload отклонён серверной проверкой Apple: «App sandbox not enabled» для трёх файлов `Resources/OpusPython/torch/bin/*`. Исправлено исключением этих инструментов; build 61 не был принят сервером.
- Локальный экспорт до исправления: pkg подписан installer-сертификатом команды; в приложении `codesign --verify --deep --strict` PASS, все 161 Mach-O подписаны Apple Distribution, xctest нет, версия 1.0/61, ID `app.kattranslator`.
- Короткий запуск archive-копии (development-подпись, sandbox): процесс стартует, система включила AppSandbox, создан контейнер `~/Library/Containers/app.kattranslator`, падений нет. Это только запуск.
- Не проверено в sandbox: скачивание моделей, Index MLX 9B/2B, OPUS GPU worker, CT2, ASR/микрофон, TTS, OCR области экрана, выбор/экспорт файлов, горячие клавиши и перевод выделенного текста через Accessibility. Магазинная сборка начинает с пустого контейнера: модели и настройки прямой сборки не переносятся.

## Открыто

- Функциональная приёмка sandbox-сборки (лучше через TestFlight для macOS).
- Перевод выделенного текста использует Accessibility и синтетический Cmd+C; в sandbox это может не работать и вызвать вопросы ревью. Есть запасные пути: буфер обмена и меню «Службы».
- Лицензии: eSpeak (GPL) и модели — открытый вопрос из `OPEN_QUESTIONS.md`, сборку не блокировал.
- dSYM для Python-расширений отсутствуют: upload выдаёт предупреждения символов, не ошибки.
- Export compliance, App Privacy для macOS и отправка на ревью не выполнялись.
