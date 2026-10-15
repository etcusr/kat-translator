# Архитектура Kat translator

[English](ARCHITECTURE.md) | **Русский**

По умолчанию на iOS, macOS и Android запись начинается и останавливается нажатием на микрофон. Сохранённый выбор режима сохраняется; удержание для записи остаётся доступно в настройках. Чтобы изменение исходников появилось в установленных приложениях, нужна новая сборка.

Общая карта компонентов. Текущие версии и ограничения — [CURRENT_STATE](CURRENT_STATE.ru.md).

## Архитектура и ключевые точки входа

| Область | Файлы/каталоги от корня | Назначение |
|---|---|---|
| iPhone entrypoint | `apps/ios/OfflineTranslatorApp.swift` | Запуск, платформенная оболочка |
| Mac entrypoint | `apps/macos/KatMacApp.swift`, `MacPlatform.swift` | Жизненный цикл, меню/окна/горячие клавиши |
| Общая Apple orchestration | `shared/apple/Conversation/AppModel.swift` | Состояние приложения, подготовка, загрузки и взаимодействие с конвейером |
| Конвейер | `shared/packages/OfflineCore/Sources/OfflineCore/ConversationPipeline.swift` | Голос/текст, поля, этапы, отмена, результаты, playback/history |
| Политики ядра | тот же каталог: `SessionController.swift`, `TranslationModel.swift`, `TranslationPrompt.swift`, `TranslationPreflight.swift` | Сессии, доступные модели, промпт, бюджет/разбиение |
| Apple MT router | `shared/apple/Translation/RoutedTranslationBackend.swift` | Выбор реального backend для модели/платформы |
| Apple MT adapters | `LlamaTranslationBackend.swift`, `OpusTranslationBackend.swift` рядом с router | Мосты в native |
| Mac GPU adapters | `apps/macos/MLXTranslationBackend.swift`, `OpusGPUTranslationBackend.swift` | Index MLX и отдельный OPUS GPU worker |
| Native Index | `shared/native/TranslationRuntime/TranslationRuntime.cpp`, `IndexMTP.cpp` | C ABI, GGUF/llama.cpp, MTP |
| Native OPUS | `shared/native/OpusRuntime` | CTranslate2, токенизация, направление и отмена |
| Mac Python workers | `shared/native/IndexMLX/index_mlx.py`, `shared/native/OpusGPU/opus_gpu.py` | Раздельные MLX/PyTorch окружения |
| Apple ASR | `shared/apple/ASR`, `shared/packages/OfflineCore/Sources/OfflineCore/RecognitionCatalog.swift` | Whisper/Meta/Ultra и политика выбора |
| Apple TTS/OCR | `shared/apple/Speech`, `shared/apple/Camera`, `shared/native/app` | Локальные голоса, платформенные/OCR adapters |
| Apple история/настройки | `shared/apple/History`, `shared/apple/Settings` | Общие экраны и сохранение |
| Mac интеграция | `apps/macos/MacGlobalHotkeys.swift`, `ScreenRegionCapture.swift`, `MacShortcuts.swift` | Выделение, буфер, область экрана |
| Android UI | `apps/android/app/src/main/java/org/openoffline/translator/android/KatApp.kt`, `MainActivity.kt` | Compose/workspaces/lifecycle |
| Android speech/OCR | там же `SystemSpeechRecognizer.kt`, `OcrRouting.kt`, `MlKitOcr.kt`, `packages/RecognitionRouting.kt` | Выбор engine и явного source language |
| Android пакеты | там же `packages/PackageRepository.kt`, `PackageDownloads.kt`, `PackageDownloadService.kt` | Integrity, lifecycle и загрузки |
| Android engines | `apps/android/inference/src/main/java/org/openoffline/translator/inference` | IndexEngine, OpusEngine, OfflineMedia, audio |
| Android native | `apps/android/inference/src/main/cpp` | JNI, CMake, scoped Mali optimizations |
| Общий каталог | `assets/catalogs` | URL/revision/размер/SHA, manifests, notices и platform capabilities |


## Контракты, которые важно сохранить

- В `TranslationModel` остаются retired enum IDs для чтения старой истории; selectable содержит `.opusBig`, `.opusDirections`, `.index2B`, `.index9B`. Наличие enum case не значит доступную модель в UI.
- У Index окно2048/input1536; preflight оставляет место ответу. Не возвращать отменённые эксперименты с соседним контекстом/настройками окна. Дробление всего текста по предложениям может ухудшать скорость и смысл.
- Старый OPUS EN-пакет поддерживает EN↔RU/UK/BE. Каталог `opus-direction-packages.json` добавляет прямые направления, включая пары без EN; маршрут и целевой маркер берутся из каталога. Не делать скрытый pivot. На современном Mac только старый EN-пакет использует PyTorch Metal FP16; новые направления используют CTranslate2 CPU INT8, как на iOS/Android.
- Отмена должна доходить до native, не публиковать устаревший результат; новый запрос после отмены должен работать. Unload не должен гоняться с inference. Отдельно проверять лимит ответа и сохранность полного исходного аудио.
- Подготовка MT и память управляются настройками autoload/memory-saving. Не путать время загрузки, ASR, перевода, TTS, записи и воспроизведения.
- Завершённый перевод должен сохраняться независимо от наличия TTS. Повтор playback не требует повторного MT; оригинальная запись и синтезированная речь — разные сущности.
- Настройки retention сохраняются сразу; pruning откладывается до закрытия, чтобы промежуточное редактирование числа не удаляло историю.
- Android voice/camera используют явный язык. Apple и text-auto имеют свою политику. Нельзя распространить поведение одной платформы на все без чтения кода.
- Android translation backends: `opus` (OPUS EN-пакет и направления), `index2b` (Index 2B, рекомендуемая многоязычная, receipt-пакет `packages/index-translate-2b-q4km.bin`, без MTP), `index` (Index 9B, «максимальное качество», прежний файл `Index-Translate-9B.Q4_K_M.gguf`, MTP). В `PackageCatalog` остаются `DEFAULT_TRANSLATION_BACKEND="opus"`, `MULTILINGUAL_BACKEND`, `INDEX_MODELS`; начальный выбор пользовательской настройки задаёт `TranslatorState` как `AUTO_TRANSLATION="auto"`, а не эта legacy-константа. 2B есть на всех платформах (`platforms: [ios, macos, android]`).
- Android перевод по умолчанию `auto`: `TranslatorState.resolveModel(from,to)` выбирает установленную модель для пары по классу устройства (`deviceClass` из теста первого запуска: `memory_probe.cpp` + `gpu_probe_matvec.cpp`, оценка 9B с запасом на нагрев 0,7; мощное → 9B/2B, среднее → OPUS/2B/9B; тест идёт до выбора языков). Настройка языков использует `PackageLanguageSetup.AUTO_STRONG`/`AUTO_COMPACT`; явный выбор модели пользователя сохраняется.
- Apple: `TranslationModel.index2B`/`.opusDirections`, `OpusDirectionRoutes` + `AutoTranslation.resolve` (OfflineCore), `OpusDirectionPackages` и `PackageDownloadCoordinator.resolvedTranslation/autoPlan` (shared/apple), `DeviceProbe.swift` (CPU + Metal, запас 0,7 только на iOS), `RoutedTranslationBackend` (Mac: MLX 9B + отдельный Llama для 2B; OPUS EN↔RU/UK/BE на GPU, направления — CT2 CPU). OpusRuntime экспортирует `ot_opus_*_direction` (`exports.txt`). На Apple «Авто» включено по умолчанию при отсутствии сохранённой модели. На мощном устройстве приоритет 9B → 2B; иначе установленный поддержанный EN-пакет → установленное направление → 2B → 9B. `ConversationPipeline` разрешает Auto-модель после определения источника, включая preview, выгружает прежнюю и сохраняет фактический ID в метриках. `refreshVoiceFiles` синхронизирует режим, а обновления голосов/ASR сохраняют resolver. Picker Auto не ограничен активной моделью. OPUS ищет первый установленный маршрут, а setup учитывает ручные пакеты; `OpusDirectionsView` скачивает через общий `DownloadButton`. Android `TranslationResources` освобождает неактивный движок и lease; EN→EN обходит inference. Экран языков Apple использует один свой язык; Android поддерживает несколько. Не считать интерфейсы и план загрузок полностью одинаковыми.
- Android OPUS: модель-направление = пакет. Маршрут (папка направления + маркер `>>xxx<<`) выбирает `PackageCatalog.opusRoute` по `opus-direction-packages.json` (генератор `scripts/android/generate-opus-pairs-catalog.py`); EN-пакет описан в коде. Общий `OpusRuntime` имеет `*_direction` API; старый API с языковой парой нужен Apple — не удалять.
- Android `kat_index` собирает CPU-часть ggml с `GGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16`. i8mm не включать без замены на рантайм-выбор вариантов (нет на Tensor G1/G2, Snapdragon 865/888). `index_jni.cpp` отказывает через HWCAP до запуска ggml. Перевод идёт через Vulkan; CPU-флаги на него не влияют.
- Кэш установленного пакета не заменяет SHA/integrity path: changed files должны перепроверяться. Сетевые ошибки, отсутствие пакета и отсутствие поддержки показываются явно.

## Модели, окружение и сборочные зависимости

`model-store/downloads` — общий кэш; `blobs/sha256` хранит некоторые файлы по digest; `research` — отдельные кандидаты. `Dependencies/downloads` — совместимая ссылка для старых скриптов. Модели не включаются в APK и не дублируются по каталогам платформ. Копии в sandbox телефонов нужны отдельно.

Каталоги: `models.json`, `voice-manifests.json`, `additional-voices.json`, `recognition-packages.json`, `android-asr.json`, `android-ocr.json`, `android-capabilities.json`, `index-mlx-package.json`, `opus-package.json`, `opus-gpu-package.json`, `opus-direction-packages.json`, notices. `scripts/generate-model-catalog.py` генерирует Apple adapter; Android подключает общий каталог через Gradle. Не редактировать generated adapter вместо canonical JSON.

Pinned inputs: `Dependencies/runtime.lock.json`, `whisper.lock.json`, `android-runtime.lock.json`, `android-media.lock.json`, `index-mlx.lock.json`; Wayu имеет собственный `shared/native/Wayu/dependencies.lock.json`. Current llama commit `d81235049384534c167caea52b85a694f6103d14`. У Index и Whisper разные GGML ABI, hidden symbols/раздельные библиотеки существенны. Android patches применяются к build-копии, не к общему vendor.

Данные прямой Mac-сборки — `~/Library/Application Support/OfflineTranslator`, вне заменяемого `.app`; магазинная sandbox-сборка хранит данные в своём контейнере. Экспорт не содержит пользовательскую историю, записи, ключи подписи или окружение. Личные sign settings — ignored `apps/ios/Config/Signing.local.xcconfig`; Android SDK/toolchain задаёт `scripts/android/env.sh`; optional `local.properties` исключён из Git.

## Практические команды

Из корня проекта, при подготовленных зависимостях. Они приведены для продолжения работы и **не запускались в рамках этой документации**.

```sh
# Проверка исходников каталогов
python3 scripts/generate-model-catalog.py --check
python3 scripts/android/generate-ui-catalog.py --check
# Swift unit tests
swift test --package-path shared/packages/OfflineCore --scratch-path .build/core
# iOS project и unsigned build
python3 scripts/generate-project.py
xcodebuild -project apps/ios/OfflineTranslator.xcodeproj -scheme OfflineTranslator \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
# Mac — подготовка runtime, project и build
bash scripts/build-macos-runtimes.sh
python3 scripts/generate-macos-project.py
xcodebuild -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/MacDerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
# Упаковка; не устанавливает приложение
bash scripts/package-macos.sh
# Отдельный совместимый пакет; сохраняет современный проект
bash scripts/build-macos15-26.sh
# Mac App Store: отдельный store-проект в .build/macos-store-project, archive и export/upload
KAT_MAC_STORE_BUILD=<n> bash scripts/archive-macos-appstore.sh export
# Android — testDebugUnitTest, lintDebug, assembleDebug/AndroidTest
bash scripts/android/build.sh
```

Android toolchain: JDK17, NDK28.2.13676358, SDK36, Gradle9.4.1; конкретные SHA в lock. Подготовка: `setup-tools.py`, `setup-vulkan-tools.py`, `setup-media.sh`, `setup-opus.sh`, `setup-omnivoice.sh`, `setup-wayu.py` в `scripts/android`. Они могут скачивать/собирать зависимости; прочитать скрипт перед запуском. SDK/tools локально в `.build/android-tools`, среду задаёт `scripts/android/env.sh`.

Device suites: `scripts/android/test-parity.sh ui|contracts|media|opus|downloads|transfers|camera|voice|cancel|recording|default|photo`; требуют предварительной установки app/test APK и fixtures. Они управляют процессом Kat, сохраняют/восстанавливают prefs; не запускать параллельно с другим опытом. Функциональные проверки по пользовательскому решению идут без температурных пауз. Для сравнения скорости нужен контролируемый нагрев/одинаковые входы, beam, runtime и модель; GPU timestamps сами добавляют overhead.

Автотесты интерфейса (проверяют экраны и выбор, без запуска скачивания моделей):
- Android — `UiLayoutAuditTest` (androidTest);
- iOS — `testPanelScreensAlignLineStarts`, `testOpusDirectionsSelectionShowsTotal`;
- Mac — `testLanguageSetupAlignsLineStartsAndActions`.

Статические проверки — `scripts/validation/test_ui_typography.py`, `test_docs_app_parity.py`. Mac UI-тестам нужны Xcode в «Универсальном доступе» и учётная запись Apple ID в Xcode → Settings → Accounts; iOS UI-тест-раннеру нужна та же учётная запись. Тесты на Pixel, iPhone и Mac можно запускать параллельно. Mac-тестовые сборки запускать из DerivedData вне `~/Downloads` (см. [Mac README](macos/README.ru.md#заметки-о-тестах)).

Установка на iPhone: `xcrun devicectl device install app --device <UDID> <.app>`; работает и по Wi-Fi. Использованный 13.10 development-профиль истекает 20.10 по результатам проверки установленной сборки; в том случае «no longer available» было вызвано истечением прежнего профиля. Новый development-кандидат с другим ID подписан профилем до14.10.2027; старый контейнер автоматически не переносится. Срок проверять у конкретной установленной версии. Перед сменой ID сохранить и проверить перенос данных; старую app не удалять до проверки. Служебные ASR/voice-transfer скрипты по умолчанию адресуют новый ID; для прежнего передавать `--bundle-id org.openoffline.translator.prototype`. Mac: `package-macos.sh` только упаковывает уже собранный `.build/MacDerivedData/.../Release` — сначала собрать.

iOS privacy manifests зависимостей: `Dependencies/privacy/ios/`. После встраивания frameworks генератор запускает `scripts/install-ios-privacy-manifests.py`: установка четырёх framework-деклараций и повторная подпись, до подписи app. Чужие vendor XCFrameworks не меняются. [Основания деклараций](../Dependencies/privacy/ios/README.ru.md). Python используется для локального Wayu: перед упаковкой исключаются `_ssl` и `_hashlib`, содержащие OpenSSL; встроенные хеш-функции сохранены, загрузки и проверка моделей работают через URLSession/CryptoKit. [Проверка удаления и ограничения](publication/ios-openssl-removal-2026-10-14.md). [Приёмка на iPhone](publication/ios-openssl-device-2026-10-14.md): реальные HTTPS-загрузки с SHA-256, ASR→Auto→TTS и тайский Wayu без этих модулей прошли. Экспортная декларация iOS задаётся в `apps/ios/Info.plist`: `ITSAppUsesNonExemptEncryption` — Boolean false. [Основание и проверка](publication/ios-export-compliance-2026-10-14.md).

iOS tests: `apps/ios/tests/ui`. Mac: `apps/macos/tests/runtime`, UI tests внутри Mac дерева. Swift tests: `shared/packages/OfflineCore/Tests/OfflineCoreTests`. Python diagnostics: `scripts/validation/test_*.py`. Большие стресс-тесты требуют отдельного включения. Сначала выбрать проверки по области изменения, не запускать всё дерево без необходимости.

## Локализация интерфейса

Apple использует `assets/bundled/Localizable.xcstrings` и `OfflineCore/L10n.swift`; строки разрешений iOS — `apps/ios/Resources/InfoPlist.xcstrings`, macOS — `apps/macos/*.lproj/InfoPlist.strings`. Поддержаны RU/EN/ES/TR, явный выбор в настройках и первый поддержанный язык системы; при отсутствии совпадения — EN.

Android использует тот же каталог и дополнительные строки `assets/localization/android-ui.json`. `scripts/generate-android-ui-strings.py` создаёт `UiStringsEn.kt`, `UiStringsEs.kt`, `UiStringsTr.kt`; `--check` проверяет синхронизацию. `UiStrings.kt` выбирает словарь и подставляет параметры за один проход, сохраняя проценты в пользовательском тексте. Уведомления загрузок учитывают сохранённый язык интерфейса. Тексты пользователя и промпты моделей через эти словари не проходят.

## Ресурсы выпуска — 14 октября 2026

Новые локальные App Store пакеты iOS 1.0 (50) / Mac 1.0 (69) содержат 42 документа лицензий и по девять privacy manifests. `scripts/install-sdk-privacy-manifests.py` добавляет отдельные resource bundles для статических/repackaged SDK и декларации Mac; OfflineCore поставляет свой SwiftPM-ресурс. Оба installers завершаются до подписи приложения; ошибки не скрываются shell-фазой.

`shared/native/app/Privacy/InferencePrivacy.c` задаёт `ORT_DISABLE_TELEMETRY=1` через `pthread_once` до первого вызова ONNX/Sherpa во всех шести точках создания OCR/Wayu/TTS/VAD/Omnilingual. При ошибке переменной SDK не запускается. Прежнего API opt-out после CreateEnv недостаточно для ONNX1.30 ProcessInfo. Проверены экспортированные IPA/PKG и состояние реального provider. App Privacy для сторонних хостингов классифицирован отдельно: iOS app manifest и Mac `Dependencies/privacy/macos/App.xcprivacy` отражают четыре категории технических данных загрузок. Декларации runtime SDK остаются отдельными и не получают эти категории. Новые app manifests включены в проверенные IPA50/PKG69, заменяющие прежние49/68; [основания и ответы](publication/model-download-privacy-2026-10-14.md). App Privacy опубликован по снимку кабинета; [пакеты50/69](publication/hosting-manifests-release-2026-10-14.md) ещё не загружены. Upstream SDK signatures и серверная обработка Apple остаются: [аудит](publication/apple-privacy-sdk-2026-10-14.md).

Общие loading-ролики поставляются из `assets/bundled/LoadingAnimations` на все три платформы. Каталог содержит 13 клипов: два ролика удалены; `cat-break` имеет английскую подпись CAT BREAK независимо от языка UI. Генератор сохраняет замену подписи при повторной подготовке. [Ресурсы и галерея](branding/loading-animations/README.ru.md).

Генераторы Apple-проектов включают `assets/bundled/ThirdPartyNotices.txt`, собираемый с проверкой SHA-256 через `scripts/assemble-ios-notices.py`. Это начальный набор атрибуций iOS; полнота прав и соответствующих исходников проверяется отдельно. [Состав и ограничения](publication/ios-release-preflight-2026-10-14.md).

## Проверки магазинной сборки Mac (14.10)

Магазинный Mac-вариант собирается `scripts/archive-macos-appstore.sh`: `generate-macos-project.py` с `KAT_MAC_STORE_PROJECT` создаёт ignored-проект `.build/macos-store-project`, где Bundle ID `app.kattranslator`, store Info.plist, `KatMacStore.entitlements` и sandbox заданы только target приложения. При `ENABLE_APP_SANDBOX=YES` `bundle-macos-runtimes.py` подписывает helpers с inherit, исключает `protoc`, OpenSSL/rustls и снимает отдельные подписи ресурсных бандлов SwiftPM. [Mac README](macos/README.ru.md) · [история сборок 61–66](publication/macos-appstore-build-2026-10-14.md).

`archive-macos-appstore.sh` резервирует отдельный каталог попытки и прекращает выполнение при ошибке архивирования/журнала; существующий архив не переиспользуется. Регрессии проверяет `scripts/validation/test_macos_store_archive.py`. В `MacRuntimeTests` opt-in засев/сброс защищён точным адресом store-контейнера и проверкой результата удаления; обычные тесты используют временные фикстуры. Результаты UI пишутся в `KAT_RUNTIME_REPORT_DIR` или временный каталог приложения. [Проверка и ограничения](publication/release-check-fixes-2026-10-14.md).

## Лицензионные ресурсы

`scripts/assemble-ios-notices.py` собирает проверяемые по SHA-256 исходные тексты из `docs/licensing/2026-10-14/ios-notices` в общий `assets/bundled/ThirdPartyNotices.txt`. Имя скрипта историческое: ресурс упаковывается в iOS, macOS и Android; Mac-дополнения помечены отдельно. Общий Apple `PrivacyView` открывает список документов офлайн. `scripts/validation/check_release_notices.py` сверяет фактический ресурс после сборки/экспорта в `.app`, IPA или APK. Наличие файла не сертифицирует полное покрытие зависимостей; границы — в [проверке комплекта](licensing/2026-10-14/release-package-review.md).

Комплект исходников: `scripts/collect-dependency-sources.py` скачивает 614 закреплённых входов по `docs/licensing/2026-10-14/dependency-sources.json` с проверкой SHA-256; `--check` работает офлайн. Большие архивы находятся в ignored `dist/licensing`. `scripts/assemble-source-notices.py` воспроизводит дополнения из проверенных архивов, не извлекая и не исполняя код. Пути подмодулей, патчи и оставшиеся границы соответствия бинарникам — в [описании комплекта](licensing/2026-10-14/source-kit.md).

## Проверки runtime и сети

`MacRuntimeTests` содержит opt-in `KAT_NETWORK_EXPECTATION=allowed|denied`: HEAD к каталожному файлу сравнивается в обычной sandbox-копии и копии без network-client entitlement. `KAT_SPEECH_INTEGRATION=1` включает полный Thai Wayu, а не только frontend. Загрузочный тест использует уникальный ID и восстанавливает liveDownloadIDs при любом исходе. `VoiceAutoRoutingIntegrationTests` проверяет повторный playback и пишет только тип выхода, частоту и состояние аудиосессии. [Прогон50/69](publication/runtime-acceptance-2026-10-14.md) выявил непостоянный iPhone-аудиосбой; эти проверки не означают TestFlight-приёмку или полную трассировку сети.

### Очистка аудиосессии (14 октября 2026)

SpeechPlayer и AudioRecorder деактивируют сессию iOS только после собственной успешной активации. SpeechPlayer наблюдает прерывания и изменения конфигурации движка, завершает ожидающее воспроизведение ошибкой, снимает наблюдателей перед разборкой и защищает поставленные в очередь callbacks проверкой идентичности движка. [Доказательства регрессии на устройстве](publication/ios-playback-fix-2026-10-14.md).

### Комплект исходников и воспроизводимость SDK

`scripts/package-dependency-sources.py` создаёт проверенные части TAR с исходниками по списку разрешённых. `scripts/rebuild-opus-source-kit.py` пересобирает изолированный Opus XCFramework из проверенных архивов и патча, добавляет manifests по платформам и при необходимости подписывает SDK. Существующие результаты vendor он не заменяет. [Происхождение и ограничения](licensing/2026-10-14/publication-and-sdk.md). Общий ресурс уведомлений теперь содержит 46 документов, включая Wayu, Supertonic 3 и условия моделей CC BY-NC.

Подпись входных speech SDK: `scripts/sign-verified-speech-sdks.py` сверяет архивы и все исходные файлы, создаёт отдельные копии и подписывает их сертификатом дистрибьютора Kat. Подпись не называется подписью upstream; полезная нагрузка не меняется. Точные source commits и embedded ONNX описаны в `docs/licensing/2026-10-14/sdk-provenance.json`.
