# Android: архитектура и история переноса Kat translator

[English](README.md) | **Русский**

Текущий выпуск — **0.4.6/code21**. Compose, текст/голос/камера, история и загрузки; Index 9B Vulkan/MTP, Index 2B Vulkan без MTP, OPUS CPU с отдельными направлениями, GigaAM/Parakeet ASR Auto. Начальный выбор перевода — «Авто» по классу устройства и языковой паре; сохранённый ручной выбор не сбрасывается. Первоначальный тест CPU/GPU идёт перед выбором языков. [Текущее состояние](../CURRENT_STATE.md) · [установка и сборка](INSTALL.ru.md) · [фактическая структура](PLATFORM_LAYOUT.md).

Свежая [голосовая приёмка RU/DE](../benchmarks/voice-auto-devices-2026-10-13/README.md): импорт и физический микрофон Pixel, GigaAM/Parakeet → Auto OPUS/Index 2B → TTS. Исходный язык Voice выбирается явно; ASR Auto означает выбор движка, не определение неизвестного языка речи.

## История переноса и первоначальные решения

Ниже сохранены оценка и этапы переноса до текущего выпуска, включая прежние планы, значения по умолчанию и результаты отдельных сборок. Они не являются действующей спецификацией или перечнем отсутствующих функций. Старое описание незакоммиченного дерева относится к периоду до очистки истории; сейчас продолжать из `main` по [Git workflow](../GIT_WORKFLOW.md).

Исторические измерения Android 0.2.1: профилировка локализовала задержку в GPU-матрицах. Выбор другого
ядра генерации на Mali-G715 сократил повтор короткой фразы с 8,51 до 7,29 с
без изменения модели. [Измерения, неудачные эксперименты и воспроизведение](benchmarks/2026-10-12-pixel9pro-index-profile/README.md).

Android0.2.2: [оптимизация prefill, профиль MTP и поиск подходов](benchmarks/2026-10-12-pixel9pro-mali-research/README.md).
Для входа82 токена prefill8,68→6,68с в диагностическом runtime, без изменений
Index/Q4_K_M. Короткий перевод в APK остаётся7,23–7,27с. MTP показывает
предварительный выигрыш в отдельной диагностике; в версии 0.3.1 он уже интегрирован.
Контролируемые замеры скорости учитывали нагрев; последующие функциональные
проверки  выполняются без пауз. История
контроллера — [здесь](benchmarks/2026-10-12-pixel9pro-thermal-mtp/README.md).

[текущее состояние](../CURRENT_STATE.md) · [Зафиксированные входные данные](portability-contract.json) · [Проверки](../../scripts/validation/test_android_readiness.py)

## Вывод

Перенос реалистичен. Предлагается **Kotlin + Jetpack Compose для Android, C/C++ через JNI для inference**, с общими файлами моделей, каталогом и проверочными примерами. Исходный baseline — ARM64 CPU; после сравнения и исправления вычислений Mali основной Android-режим — Vulkan GPU. Наличие Tensor G4 не означает, что произвольная GGUF-модель сможет использовать его TPU.

Поддержка Android у upstream-библиотеки подтверждает путь переноса, но не скорость, устойчивость или совместимость конкретной версии Kat. **На Pixel проверены Index, OPUS, Whisper, Piper, Supertonic, Wayu, OCR, камера и полный сценарий импорт → распознавание → Index → озвучка → экспорт. OmniVoice исправлен и прошёл реальный синтез; все 8 проверок исправленного меню и настроек прошли. Распознавание Whisper и OmniVoice пока медленные.**  дальнейшие функциональные тесты идут без температурных пауз, отдельно от сопоставимых замеров производительности. Локальные JDK 17, SDK/NDK и ADB установлены в `.build/android-tools`. Pixel: Android 17/API 37, 4-КБ страницы, около 16 ГБ RAM. Сборки Apple после миграции были проверены на предыдущем этапе. Исходные измерения: [описание сохранённых материалов](benchmarks/2026-10-11-pixel9pro-index-cpu/README.md).

Источники проекта: актуальные разделы `docs/CURRENT_STATE.md`, `README.md`, два генератора Xcode-проектов, `shared/native/`, `shared/packages/` и `assets/catalogs/`. Исторические модели в старых отчётах не включены в основной Android-набор. В рабочем дереве много существующих незакоммиченных изменений; реорганизация выполнена поверх актуального дерева с сохранением исходного снимка и без сброса изменений.

## Архитектура и альтернативы

| Вариант | Что сохраняется | Цена и решение |
|---|---|---|
| **Kotlin/Compose + общий C/C++** | Веса, токенизаторы, C ABI, каталог, эталонные данные | Рекомендация: предсказуемая интеграция камеры, звука, lifecycle; Swift-политику переносим с тестами соответствия |
| Kotlin UI + выделенное Swift-ядро | Часть чистой бизнес-логики Swift | Реальный вариант: официальный Swift SDK для Android существует. Но текущий `OfflineCore` содержит AVFoundation, Combine, NaturalLanguage, Darwin, ImageIO; потребуется выделять переносимый пакет и добавлять ещё один toolchain |
| Flutter + C/C++ | Веса и inference | Потребует нового UI и мостов к платформам; для первого Android-порта не даёт автоматического переиспользования SwiftUI |

SwiftUI, Vision, Metal, CoreML и AVFoundation не переносятся вместе со Swift SDK. Поэтому предложение Kotlin связано с составом текущего проекта, а не с утверждением, что Swift не работает на Android. [Swift SDK](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).

## Единая структура репозитория

Целевая структура после отдельной проверенной миграции:

```text
apps/
  ios/                         # iOS entrypoint, камера, widget, plist, Xcode-проект, UI-тесты
  macos/                       # Mac entrypoint, hotkeys, menu bar, plist, Xcode-проект, UI-тесты
  android/                     # Gradle, Compose, Android services, JNI, instrumentation
shared/
  apple/                       # общие iOS/macOS SwiftUI-экраны и Apple adapters
  packages/                    # OfflineCore и SpeechRecognitionRuntime; пока Apple-пакеты
  native/                      # TranslationRuntime, Whisper glue, TTS, OCR, fastText
  contracts/                   # форматы каталогов, история, golden fixtures
assets/
  catalogs/                    # единый источник метаданных моделей и голосов
  bundled/                     # небольшие общие ресурсы: lid.176.ftz, словари, графика
  licenses/                    # model cards, notices, лицензии
model-store/                   # игнорируется Git; один локальный кэш весов на компьютере
  blobs/sha256/                # каждый универсальный файл хранится по digest один раз
  packages/                   # состав пакетов: ссылки на blobs, не копии весов
dependencies/
  locks/                      # commit, patch digest, SHA-256 и build options
  vendor/                     # исходники движков; общий кэш, вне Git
scripts/
  ios/
  macos/
  android/
  validation/
tests/fixtures/               # общие текстовые, аудио- и OCR-примеры
docs/                         # инструкции и отчёты
.build/<platform>/<abi>/       # платформенные результаты, вне Git
dist/<platform>/              # подписанные установщики, вне Git
```

**Миграция платформ выполнена; фактические пути приведены в [карте каталогов](PLATFORM_LAYOUT.md).** Ниже сохранён первоначальный план переноса. Универсальные модели остаются в общем хранилище, без копий для каждой платформы.

Карты переноса:

- `App/` нельзя целиком назвать `apps/ios`: `scripts/generate-macos-project.py` включает большую часть его файлов. Общие экраны Conversation, History, Models, Settings и Apple-адаптеры переходят в `shared/apple/`; iOS entrypoint, UIKit-камера и Live Activity — в `apps/ios/`.
- `MacApp/` → `apps/macos/`; `DownloadActivity/` и `Shared/DownloadActivityAttributes.swift` → `apps/ios/`; `Shared/CatProgressDrawing.swift` → `shared/apple/`.
- `Packages/` → `shared/packages/`; C/C++ части fastText/archive выделяются в `shared/native/` с корректировкой SPM-ссылок. `Native/` и C glue из `App/ASR`, `App/Speech`, OCR → `shared/native/`, с отдельными platform adapters.
- `App/Resources/*-package*.json`, `voice-manifests.json`, `additional-voices.json`, параметры моделей из Swift → `assets/catalogs/`. Разделять catalog API по платформам через capability-фильтр, а не через копирование JSON.
- Универсальная графика, словари OCR, fastText и voice previews → `assets/bundled/`. Asset catalogs, InfoPlist иконки/локализации платформ остаются у своей платформы либо генерируются из общего источника.
- Xcode-проекты, schemes, относительные SPM-пути, bridging headers, скрипты упаковки, build identity и тестовые fixture-пути обновляются в одной миграции. Регистрозависимый Linux CI проверяется отдельно: `Shared` → `shared` и `Dependencies` → `dependencies` на macOS выполняются через промежуточное имя.

### Модели и голоса без дублирования

Один каталог описывает `{id, revision, engine, format, artifacts, languages, license, platformStatus}`. Каждый artifact имеет `sha256`, `byteCount`, URL и безопасный относительный путь. Идентичность файла — digest, а не название приложения или расширение. Универсальные GGUF/GGML/ONNX/SPM/словари не раскладываются по трём `apps/`.

`model-store/blobs/sha256/<digest>` — один неизменяемый blob на компьютере разработчика. Пакет — manifest со ссылками на blobs. Поскольку ряд движков ждёт соседние файлы с определёнными именами, resolver может создать read-only hardlinks в `model-store/packages/<id>/<revision>/` на той же файловой системе; при невозможности hardlink использовать прямое разрешение путей/явный staging, не скрытые постоянные копии во всех приложениях. Проверять изменение blob перед повторным использованием.

Это хранилище предназначено для разработки и испытаний. **На разных физических устройствах модели неизбежно скачиваются отдельно**, в приватное хранилище приложения. Бинарники движков также различаются: Mach-O/XCFramework для Apple и ELF `.so` для Android не универсальны. Небольшие ресурсы могут входить в каждый установщик, но имеют один источник в репозитории. Скачивание 5,78 ГБ Index не входит в APK; импорт из файла копирует/перемещает его в приватное хранилище, а не рассчитывает на прямой `mmap` произвольного Android `content://` URI.

CoreML `.mlmodelc` помечается `apple-only`; общий файл ONNX помечается переносимым кандидатом, но `android=verified` ставится только после smoke-теста конкретного digest. Успешный парсинг каталога не повышает этот статус.

## Библиотеки: что переносится и что заменить

| Компонент и версия проекта | Android-путь | Статус / необходимая работа |
|---|---|---|
| llama.cpp `d81235049384534c167caea52b85a694f6103d14` (`v0.6.0`) | NDK/CMake, CPU ARM64, затем Vulkan | Upstream имеет Android binding. Собрать именно pinned commit. Наш `TranslationRuntime.cpp` задаёт `n_gpu_layers=99` и forced Flash Attention: вынести backend, offload и FA в конфигурацию; CPU baseline — offload=0 |
| whisper.cpp `927cfce34f31707e17f2bff35c349632fb9e2c3a` (`v1.9.4`) | NDK; тот же GGML файл | Есть официальный Android example. Apple `use_gpu=true` не переносить слепо; CPU baseline и отдельная оценка Vulkan |
| sherpa-onnx `v1.13.8`, commit `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf` | Android JNI/C API | Есть Android приложения, в том числе Supertonic. Требуется Android-артефакт вместо XCFramework, проверка операторов, data files и 16-КБ ELF |
| ONNX Runtime: iOS lock `1.28.1`, Mac script использует `1.30.0` | Один согласованный Android ORT CPU build | Это уже разные версии в проекте. Согласовать версию с sherpa, зафиксировать commit и SHA Android AAR/so; проверить Wayu/OCR/ASR. Не паковать два конфликтующих `libonnxruntime.so` |
| Piper/VITS, eSpeak NG, фонемизация | sherpa C API и его зависимости, data directory | ONNX переносим; нельзя забыть словари, espeak-ng-data и notices. Лицензия runtime не заменяет лицензии каждого голоса |
| Silero VAD `643854` bytes | sherpa/ORT на CPU | Переносимая ONNX-модель; сохранить 16 kHz input и state/reset между записями |
| fastText `v0.9.2`, `lid.176.ftz` | C++17 + JNI | Исходники уже в проекте. Apple NaturalLanguage участвует в неоднозначных/коротких фразах; Android fallback требует новых правил и тестов, без молчаливого объявления равенства |
| CTranslate2 `v4.6.0`, commit `617405f4b050e994e829d527da6caa0e0030afe7` | NDK + RUY, `WITH_ACCELERATE=OFF` | Второй приоритет после Index. Текущий CMake Apple-only. RUY в этом commit содержит INT8 и FLOAT GEMM; проверить реальные attention GEMM/leading dimensions. Сохранить `mobile-cancel.patch` |
| SentencePiece `v0.2.1`, commit `31646a467d2051eb904e0b45de3a73e91fe1c1e3` | C++17 static, без training/CLI | Нужно для OPUS, не для GGUF Index, где токенизатор входит в файл |
| OmniVoice `53e6c2066150802ad3cd4b655b31c696e78e0019` | Отдельный NDK runtime | Есть локальный cancellation patch. Сейчас OBJC, Metal, Accelerate и Apple export list в CMake; полноценный перенос ещё не доказан |
| Wayu ONNX + Python G2P | ORT + Android Python frontend либо native port G2P | Сам ONNX не решает тайскую фонемизацию. `WayuFrontend.c` содержит `mach-o/dyld.h` и Apple paths. Сначала проба Chaquopy с закреплёнными tltk/pythainlp/словарями; без сетевого скачивания ресурсов во время речи |
| FluidAudio / Parakeet Ultra CoreML | Этот пакет исключить из Android-каталога | Требует другого ONNX-export и новых измерений, если функция понадобится; не конвертировать обещанием |
| Apple Speech, CoreML, Metal, Accelerate | Whisper/sherpa, CPU/Vulkan, RUY | Apple API на Android отсутствуют; системный облачный ASR/TTS не использовать как скрытый fallback |
| Vision / текущий HybridOCR | CameraX + полный detector/recognizer OCR на ORT | В репозитории только RU/EN recognizers; detector сейчас Vision. Добавить и закрепить ONNX detector, preprocessing, NMS/boxes, orientation и CTC decode |
| AVFoundation, UIKit, AppKit, ImageIO | AudioRecord/AudioTrack, MediaCodec/MediaExtractor, CameraX, Android image APIs | Переписывается platform layer: pause, stop, audio focus, routing, rotation, capture/import/export |
| Combine/SwiftUI/Observation | Compose + ViewModel + StateFlow/coroutines | Сохранить состояния и отмену конвейера, не переносить UI файлы механически |
| CryptoKit, URLSession, archive C/bz2 | MessageDigest SHA-256, HTTP download adapter, tar/bzip2 library | Range/ETag, atomic rename, защита от traversal/symlinks, disk-full; системного bz2 в NDK не предполагать |
| History, preferences, Share sheet | Room/DataStore, FileProvider, Android Sharesheet | Импорт/экспорт общего schema, правила retention и исключение приватных данных/весов из backup |

Upstream: [llama Android](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md), [Whisper Android](https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.android/README.md), [sherpa Android](https://k2-fsa.github.io/sherpa/onnx/android/index.html), [Supertonic Android](https://k2-fsa.github.io/sherpa/onnx/tts/all/English/supertonic-3-en.html), [ORT Android](https://onnxruntime.ai/docs/build/android.html), [CTranslate2 build options](https://opennmt.net/CTranslate2/installation.html), [SentencePiece](https://github.com/google/sentencepiece), [fastText model](https://fasttext.cc/docs/en/language-identification.html).

### Особые риски сборки

- llama.cpp, whisper.cpp и OmniVoice несут собственные версии ggml. Не объединять все static ggml в одну библиотеку. Изолировать inference-модули в `.so`, скрыть внутренние символы export/version script, наружу оставить только JNI/C ABI. Проверить symbol interposition и многократную загрузку всех движков в одном процессе. Для всех библиотек согласовать NDK и `libc++_shared.so`.
- CPU — обязательный путь. Базовую сборку не собирать с глобальным `-march=native`/необязательными инструкциями Tensor/нового Snapdragon. Vulkan может не поддержать отдельные операции/FA либо создать второй набор весов в RAM; это проверяется на устройстве. NNAPI/QNN/NPU не являются обязательными зависимостями первого порта.
- 16-КБ совместимость проверяется у **каждой** `.so`, включая транзитивные ORT, Python, C++ runtime; также у ZIP packaging. NDK r28+ выравнивает ELF по умолчанию, но не исправляет чужие prebuilts. [Android 16 KB](https://developer.android.com/guide/practices/page-sizes).
- Предлагаемый совместимый набор инструментов: JDK 17, AGP 9.2.0, Gradle 9.4.1, NDK `28.2.13676358`, CMake 3.22.1, `compileSdk/targetSdk=36`, `minSdk=31`. Это стартовая конфигурация, не проверенная сборка. AGP 9.2 выбран в том числе потому, что Chaquopy 17 документирует тестирование до AGP 9.2; Android-плагины Compose/Room/KSP фиксируются вместе после dependency resolution в этапе 1, без `+`/`latest`. AGP 9 использует built-in Kotlin: не подключать второй несовместимый Kotlin Android plugin. [AGP matrix](https://developer.android.com/build/releases/agp-9-2-0-release-notes), [Chaquopy requirements](https://chaquo.com/chaquopy/doc/current/android.html).
- ML Kit не принимается как автоматическая замена всей камеры. Документация Android SDK перечисляет Latin/Chinese/Devanagari/Japanese/Korean зависимости; общий language list содержит также отдельные упоминания Cyrillic. Для RU/EN нужен воспроизводимый тест конкретного SDK/модели, поэтому основной план — полный PP-OCR pipeline. Если позже используется ML Kit, брать bundled-вариант и проверять cold start без сети. [Android OCR dependencies](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), [language list](https://developers.google.com/ml-kit/vision/text-recognition/v2/languages).

## Модели и объём файлов

Размеры ниже взяты из текущего кода/манифестов, в десятичных МБ/ГБ. Это **размер файлов, не потребление ОЗУ**.

| Модель / пакет | Скачивание | Установленные данные / Android-статус |
|---|---:|---|
| **Index-Translate 9B Q4_K_M** | **5 780 090 304 bytes / 5,78 ГБ** | Тот же GGUF, 5,38 GiB; первый обязательный device test |
| Whisper large-v3-turbo F16 | 1 624 555 275 bytes / 1,62 ГБ | Сохранить baseline; более лёгкий Whisper выбирать только после сравнения качества |
| Piper Denis + LJ Speech | 183,01 МБ архивов | 213,34 МБ суммарно по file manifests; возможна дедупликация общих data files |
| Supertonic 3 INT8 | 128,77 МБ | 145,32 МБ; кандидат на основной многоязычный TTS после тестов |
| Meta Omnilingual 300M INT8 | 292,31 МБ | 366,71 МБ; дополнительные ASR-языки, не все 1600 автоматически доступны UI Kat |
| Wayu Thai | 331,72 МБ | Три ONNX + voicepacks; Python/runtime/data увеличивают итог |
| OmniVoice Q8, base + codec | 945,28 МБ | Два GGUF; отдельная сложная ветка переноса |
| RU/EN OCR recognizers | 15,70 МБ | Требуется дополнительный detector, его размер ещё не включён |
| fastText lid.176.ftz | Уже bundled, 938 013 bytes | Общий небольшой файл; MIT у кода, CC BY-SA 3.0 у модели |
| OPUS Big INT8 | 492 650 422 bytes | Два направления; дополнительный этап, не первый MT |
| Parakeet Ultra `.mlmodelc` | Не скачивать на Android | Apple-only пакет |

Index сохраняет revision `d01404384ba429b93f5f63d43573812d103b5bcd`, SHA-256 `9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713`, окно **2048**, максимум запроса **1536**, резерв ответа `ceil(sourceTokens * 1.5) + 64`. Сохраняются исходный китайский prompt и control tokens; сравнивается фактическая токенизация pinned runtime. Длинный текст делится с retry при исчерпании лимита, успех с молчаливо обрезанным ответом запрещён.

Карточка [Index GGUF](https://huggingface.co/IndexTeam/Index-Translate-9B-GGUF) указывает Apache-2.0. Для голосов нельзя переносить одну лицензию на весь каталог: `additional-voices.json` содержит в том числе CC BY-NC 4.0, CC BY-SA и индивидуальные notices. Сохранять исходные лицензии на файлы и отдельно проверять выбранный дистрибутив перед публикацией.

## Минимальные системные требования

**Это начальные инженерные ориентиры, не подтверждённые измерениями на Android.** Публичный минимум определяется после матрицы испытаний.

| Параметр | Первоначальный порог для Index | Рекомендуемый / основное устройство |
|---|---|---|
| ОС | Android 12 / API 31 | Фактически установленная ОС Pixel 9 Pro; записать перед тестом |
| Архитектура | 64-битная ОС, `arm64-v8a`, NEON; без обязательного NPU | Tensor G4; дополнительно Snapdragon и MediaTek |
| Физическая ОЗУ | **12 ГБ — экспериментальный нижний кандидат** | **16 ГБ**; Pixel 9 Pro имеет 16 ГБ по спецификации |
| Свободное место | **15 ГБ** перед начальной установкой Index + Whisper + базовых голосов | **20 ГБ** для обновления/дополнительных пакетов; проверять расчётом перед каждым скачиванием |
| GPU | Нужен Vulkan для основного режима Index | Проверен Mali-G715 на Pixel9Pro; другие GPU требуют тестов |
| Микрофон/камера | Только для соответствующего режима | Отказ в разрешении не блокирует текстовый перевод |
| Сеть | Для получения моделей/обновлений | После подготовки inference работает офлайн, в том числе после перезапуска |

ОЗУ Pixel и процессор: [официальные характеристики Google](https://support.google.com/pixelphone/answer/7158570?hl=en-GB5). Не вся физическая память доступна процессу. `largeHeap`, swap и mmap не дают гарантии отсутствия low-memory kill.

Начальная оценка MT working set: примерно **7–10 GiB** с запасом на веса, KV, activations, runtime и UI; это гипотеза для измерения PSS/RSS, не формула точного потребления. Vulkan может изменить её в обе стороны. На 12-ГБ устройстве начинать с выгрузки Whisper перед Index, выгрузки Index перед TTS; на Pixel сначала такая же безопасная последовательность, а удержание движков в RAM включать после измерений. Нельзя ждать обработки 30 минут аудио в одном огромном буфере: chunking, ограниченные очереди и файлы на диске.

8-ГБ устройства не объявлять поддержанными для Index до успешного отдельного эксперимента. Замена основной модели OPUS ради уменьшения требований не соответствует текущему заданию.

Свободное место считается по уникальным digest: недостающие blobs + временные архивы + распаковываемые данные + сохраняемая старая версия при обновлении + резерв. Не считать простое переименование `.partial` копированием всего GGUF; не считать размер сжатого tar.bz2 размером установки. История и пользовательские записи в этот бюджет добавляются отдельно.

## План испытаний и критерии готовности

1. **Контракты на компьютере**: целостность metadata, отсутствие путей выхода из каталога, уникальность путей, закреплённые Index/Whisper и runtime revisions. Автоматизация уже добавлена, но файлы удалённых весов заново не скачиваются и не хешируются.
2. **Сборка/упаковка**: Gradle unit tests, lint, NDK build, проверка ELF/ZIP 16 KB, подписи APK, ABI, versionCode; R8 release smoke. Наличие `.so` без вызова модели недостаточно.
3. **Нативные тесты на Android**: Index load/tokenize/decode/cancel/unload с реальным GGUF; parity tokenizer/prompt с Apple; ASR fixture → текст; TTS → конечные PCM samples и ненулевая длительность; OCR → текст/boxes. Отсутствие весов — явный FAIL для acceptance job, не зелёный skip.
4. **Интеграция/интерфейс**: авиарежим и новый cold start, отказ разрешений, pause/stop, поворот, фон/возврат, audio focus, процесс убит системой, докачка Range, смена ETag, disk-full, неверный SHA, отключённая история, пустой и длинный текст, stale callback после отмены, восстановление после обновления.
5. **Качество и ресурсы**: Pixel 9 Pro 16 ГБ + минимум один ARM64 12 ГБ Snapdragon и один MediaTek/Samsung при доступности. Эмулятор нужен для API/lifecycle/16 KB, его скорость не считается скоростью телефона. 8 ГБ — отдельный отрицательный/экспериментальный класс.

Для каждого device-run сохранять модель устройства, API, ABI, page size, RAM/availMem, thermal status, backend, driver, build/runtime/model digest, cold/warm load, TTFT, tokens/s, end-to-end, peak PSS/RSS и причину завершения. Пользовательский текст и голос в общую телеметрию не включать; использовать согласованные fixtures.

Предварительные критерии приёмки Pixel, подлежащие проверке: 100 последовательных коротких переводов без crash/ANR/успеха с обрезкой; 20-минутный чередующийся голосовой сценарий без OOM; отклик UI на Stop ≤250 мс и завершение native job в пределах 2 с для короткого теста. Для usability измерять warm TTFT и полное время: целевой ориентир p95 ≤10 с до первого токена и ≤30 с для перевода исходника из 20–40 слов. Если Index медленнее, показать фактический результат и оптимизировать; не объявлять эти цифры достигнутыми и не подменять модель. Качество MT оценивается по согласованным эталонам/числам/именам и ручной билингвальной выборке, а не по одному непустому ответу.

## Что проверено сейчас

Добавлены `scripts/validation/android_readiness.py` и `test_android_readiness.py`; используются только стандартные библиотеки Python.

```bash
python3 -m unittest discover -s scripts/validation -p test_android_readiness.py -v
python3 scripts/validation/android_readiness.py
# Когда настоящий ARM64 APK появится:
python3 scripts/validation/android_readiness.py --apk dist/android/kat-translator.apk
```

APK-проверка проверяет ELF64/AArch64, PT_LOAD и ZIP alignment ≥16 KB для uncompressed `.so`, наличие manifest/DEX и отсутствие duplicate ZIP entries. Это строгая политика нашего будущего ARM64 release, а не универсальный Android APK validator: compressed `.so` намеренно отклоняются. Она **не** проверяет подпись, корректность DEX/manifest, полноту JNI symbols, model execution, зависимости `DT_NEEDED` или реальную загрузку на устройстве; это отдельные обязательные этапы плана. Тестовые APK синтетические и не выдаются за приложение.

Результаты текущего запуска: **31 тест проходит; 7794 записи файлов в существующих JSON-манифестах проверены**. Зафиксирован primary Index и два runtime commit. Негативные тесты подтверждают, что подмена primary на OPUS, изменение SHA Index или commit llama обнаруживаются. `apk_packaging=NOT_RUN`, `android_inference_verified=false`. Логи: `.build/android-readiness/tests.log`, `.build/android-readiness/source-audit.json`. Существующие Swift/Apple build tests на этом этапе не запускались: исходники приложения не менялись. JDK/SDK/NDK и модели не устанавливались.
