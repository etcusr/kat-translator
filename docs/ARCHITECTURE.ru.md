# Архитектура Kat translator

[English](ARCHITECTURE.md) | **Русский**

**Промежуточный интерфейс iOS:** `AppModel` включает `ConversationPipeline.showsTranslationPartials` на iOS; сам pipeline по-прежнему ограничивает его Index 9B. `ConversationView` использует показ прогресса над рабочей областью на протяжении запроса, как Mac, для текста/голоса; убирает дублирующие нижние действия/прогресс текста и однократно открывает результат при первом фрагменте. Итоговые поля и история отделены. Камера и OPUS не меняются. [Проверки](publication/ios-partial-text-2026-10-20.md).

**Проверка установленной iPhone-сборки, 20 октября:** development 1.0.1 (56) заменяет Store 1.0 (55) поверх, с прежним идентификатором приложения и постоянным хранилищем. Подтверждены готовность Index/Whisper и сохранённые файлы моделей/голосов; недоступность Store-контейнера не позволяет сравнить все хэши до/после. OPUS размером 492,7 МБ скачался при свёрнутом Kat с уведомлением о готовности; паузы процента сохраняются. На этом предыдущем этапе сборки 56 ролики ожидания были удалены, а промежуточный текст оставался только на Mac; сборка 57 выше заменяет это состояние интерфейса. [Проверки и ограничения](publication/ios-update-acceptance-2026-10-20.md).

**Отправка прогресса и сохранность при обновлении:** `DownloadLiveActivity.flush()` ожидает публикации ревизии вызывающего кода, включая снимок в очереди за уже отправляемым обновлением. `ModelDownloader.urlSessionDidFinishEvents` ждёт её до вызова системного completion handler; обновления при смене состояния SwiftUI-сцены используют короткое истекающее разрешение фоновой работы. Это не удерживает загрузчик в приложении: фоновые передачи URLSession выполняет система. `staleDate` включает часы/пояснение в Island через 60 секунд без публикации. Модели остаются в Application Support/OfflineTranslator; при обновлениях сохраняются идентификатор приложения, ID моделей и хэши неизменившихся файлов. [Проверки и условия выпуска](publication/ios-download-activity-2026-10-20.md).

Прогресс ImageTranslationSession охватывает всю сцену: знаменатель — все символы исходника, части — OCR-блоки, доля готовности внутренних частей взвешивается по длине активного блока. Кэш учитывается сразу; прогресс сохраняется между запросами и не откатывается внутри сцены. Новая сцена сбрасывает его; поздние callbacks по-прежнему защищены. Группировка OCR и запросы к движку не менялись.

**Модель перевода в памяти и опциональные части на Mac:** `RoutedTranslationBackend` оборачивает Mac-движки в `RetainedTranslationBackend`; последовательный доступ согласует перевод, смену модели и выгрузку по простою. Следующий запрос загружает сохранённую выбранную модель. По умолчанию 300 секунд; `macTranslationIdleMinutes` сохраняет настройку 1–60 минут. Явная выгрузка забывает выбор, экономия памяти сохраняет приоритет. `macExperimentalTranslationChunks` по умолчанию true (явно сохранённый выбор сохраняется) и включает планировщик `TranslationChunks` по 128 исходных токенов только в Mac MLX/Index 9B. Поля диалога отделяют промежуточный показ от итогового текста/истории; callbacks защищены идентификатором запроса. iOS не создаёт обёртку хранения и не показывает эти настройки. [Проверки](benchmarks/mac-production-residency-2026-10-20/README.md). На Mac активный запрос с промежуточным текстом использует закреплённую строку прогресса и отмены над рабочей областью, без перекрывающего экрана и GIF. Этот показ сохраняется до завершения/отмены; начальное распознавание речи и обычный перевод используют прежний интерфейс. Mac-сеанс изображений также показывает текст текущего блока отдельно от готовых данных/кэша/истории; идентификаторы запроса и сцены отсекают поздние callbacks. Все приложения исключают архивные ролики/постеры/плейлисты ожидания; реализации видеопроигрывателей удалены.

Расширение iOS `DownloadActivityExtension` реализует только ActivityKit Live Activity для загрузок моделей. `DownloadActivityBundle` регистрирует `ModelDownloadActivity` через `ActivityConfiguration`; обычного виджета с timeline для домашнего экрана/экрана блокировки и записи в галерее не предусмотрено. `ModelDownloader.start` запускает активность при активном приложении и разрешении системы. [Диагностика ревью и границы проверки](publication/ipad-widget-review-2026-10-19.md).

**iOS 1.0 (55) проверена и загружена в App Store Connect** с исправлением громкости оригинала. Владелец проверил development 54 и сообщил, что результат в порядке; это была установленная на тот момент сборка (заменена обновлением выше). Подписи, содержимое IPA и 143 проверки проекта прошли. Обработка Apple и установка Store 55 через TestFlight пока не подтверждены; выбор сборки для App Review остаётся владельцу. Локально сохранены Store 53/54/55. [Проверки и загрузка](publication/ios-original-volume-2026-10-18.md).

**Development-исправление установлено на iPhone 1.0 (54), `ios-ff3ccf9891771b76`:** тихие оригинальные записи микрофона на iOS/Mac получают отдельное ограниченное усиление при сохранении для воспроизведения, экспорта и истории. На предоставленном M4A уровень вырос с −44,75 до −16,13 dBFS RMS без изменения длительности и переполнения после декодирования. Вход распознавания и TTS не менялись. Тесты общей библиотеки, подписанная сборка iOS, проверка подписи, установка и обычный запуск прошли. Владелец проверил установленное development-исправление и сообщил, что результат в порядке; независимая новая акустическая проверка не заявляется. [Проверки и ограничения](benchmarks/apple-original-level-2026-10-18/README.md).

Локальные DMG/ZIP обновлены до **0.6.8 (61)** для macOS 27+ и отдельно macOS 15–26. В обоих комплектах есть актуальные исправления распознавания/озвучки и вкладки «Изображение», включая абзацы и диагностические таймеры. Распаковка, подписи, контрольные суммы и ограничения библиотек проверены. Храним не более трёх выпусков на канал: основной 59/60/61, совместимый 53/61 (пока существуют два). Установленная исправленная копия остаётся 0.6.7 (60). [Проверки пакетов](publication/mac-direct-2026-10-18.md).

**iOS 1.0 (54) и Mac App Store 1.0 (76)** проверены и загружены в App Store Connect. Включены подготовка распознавателя до микрофона, освобождение распознавания на вкладках «Текст»/«Камера» и настройка исправления даты/времени, выключенная по умолчанию. На iPhone захват через AudioQueue сокращает задержку первого аудиобуфера примерно с 1,40 до 0,28 с по development-замерам. Обработка во время записи и предыдущие исправления потоковой озвучки сохранены. Mac также объединяет OCR-строки в абзацы и показывает время распознавания/перевода при включённой диагностике. Подписи, права доступа, ресурсы и все 143 проверки проекта прошли проверку. Обработка Apple и установка через TestFlight ещё не подтверждены; сборки для App Review выбирает владелец. [Проверки и загрузка](publication/apple-capture-store-2026-10-18.md).

На Mac вкладка «Изображение» объединяет близкие OCR-строки в абзацы до перевода, убирает лишние переносы/отступы внутри перевода и сохраняет отдельные заголовки, абзацы и пункты списка. При включённой диагностике справа показываются время распознавания и перевода; загрузка моделей не входит в эти значения, кэш даёт нулевое время нового перевода. Живая камера iPhone сохраняет прежнюю группировку. [Проверки и ограничения](benchmarks/mac-image-paragraphs-2026-10-18/README.md).

На iPhone `AudioRecorder` использует входной `AudioQueueCapture`: Float32 PCM с чередованием каналов на частоте устройства, три буфера по 2048 кадров и прежний путь `RecordingSink`/`AudioNormalizer`/VAD. Запуск выполняется вне главного потока и завершается только после копирования первого буфера в приёмник. До возврата продолжения очередью владеет операция запуска; отмена через поколение сразу приостанавливает приёмник, затем освобождает очередь. Остановка освобождает захват и деактивирует только собственную активированную сессию. Пауза/продолжение используют очередь текущей записи; в простое микрофон не работает. macOS сохраняет AVAudioEngine. [Замеры и проверки](benchmarks/ios-microphone-start-2026-10-18/README.md).

Нахождение распознавателя в памяти определяется текущей вкладкой ввода, независимо от режима последнего результата. Подготовка «Голоса» ждёт выбранный ASR до появления микрофона; «Текст»/«Камера» сразу снимают готовность и освобождают ASR после завершения активного нативного вызова. Номера поколений не дают устаревшей загрузке выставить готовность. Поздняя неотменяемая загрузка освобождается, если текущей вкладке распознавание уже не нужно. При экономии памяти подготовка «Голоса» загружает только ASR, откладывая MT; нехватка памяти снимает готовность и требует новой подготовки. Android кэширует Whisper, NeMo и Omnilingual с привязкой к владельцу нативного контекста. Для системного распознавания готовится/проверяется служба, но загрузкой моделей ОС приложение не управляет. Камера Apple сохраняет прежнюю политику отдельного переводчика и полной выгрузки. Внешний текст на Mac может дождаться подготовки ASR и освободить его перед переводом.

Исправлением даты и времени Whisper управляет сохраняемая настройка `whisperDateTimeRepair` в iOS, macOS и Android. По умолчанию она выключена; значение фиксируется в начале каждого вызова распознавания. Выключенная настройка означает один обычный проход и неизменённый исходный текст. Включённая допускает повтор только для русских записей до 30 секунд с одной допустимой тройкой времени/дня через точки или дефисы перед месяцем. Повтор запрещает цифровые токены, отключает временные метки и ограничивает результат 256 токенами. Замена на `H:MM, D месяц` требует точного совпадения окружающих слов, чисел и порядковой формы дня; при ошибке сохраняется исходный текст, отмена передаётся вызывающему коду. Android повторно использует тот же кэшированный контекст и владеющую им библиотеку baseline/arm82/i8mm. [Проверки и ограничения](benchmarks/date-setting-capture-2026-10-18/README.md).

Android Whisper добавляет `kat_whisper_i8mm` с отдельными именами JNI и проверкой HWCAP/HWCAP2 в базовом коде (FP16, dotprod, i8mm). Путь выбирается только для проверенного имени файла Q8; F16 и другие модели сохраняют ARMv8.2/базовый путь. `WhisperModelCache` связывает каждый нативный handle с создавшим его движком и освобождает через владельца перед заменой. Native setup готовит все три библиотеки; ошибка загрузки дополнительной библиотеки сохраняет прежние резервные пути. Веса, число потоков, окно контекста и декодирование не меняются. [Замеры и альтернативы](android/benchmarks/2026-10-17-whisper-i8mm/README.md).

Android Piper теперь передаёт нативные PCM-фрагменты в одну сессию `SpeechStream`/`AudioTrack`. Итоговый нативный массив сверяется со всеми фрагментами и автоматически повторно не проигрывается. Из тех же нормализованных фрагментов собирается звук для повтора и экспорта. Остановка отменяет отложенные UI-вызовы; завершение дожидается всех сэмплов. Начальные фрагменты накапливаются минимум до 0,8 с (либо до конца более короткой фразы), чтобы выбрать один ограниченный коэффициент громкости на весь поток. Воспроизведение начинается с запасом не менее четырёх секунд готового PCM либо всей завершённой более короткой фразы, чтобы короткое начало не опережало синтез следующего предложения.

`OfflineMedia` удерживает один выбранный контекст Whisper и один голос Piper; изменение пути/размера/времени файла заменяет модель. Голос может загружаться параллельно переводу. Удержание кэша после обработки требует общей RAM от 11,5 ГБ и свободной памяти не меньше max(2 ГБ, удвоенный системный порог нехватки памяти), вне режима экономии. Явная подготовка «Голоса» сохраняет выбранный ASR до записи, смены вкладки или нехватки памяти, даже когда удержание после обработки выключено. Запас памяти проверяется между этапами и раз в 15 секунд в простое на переднем плане; фон, явная выгрузка, операции с пакетами и закрытие освобождают модели. При смене голоса единственная ячейка голоса перезагружается. Перевод пока завершается до начала потока Piper; озвучка частичного перевода на Android не реализована. Остальные голоса синтезируют полный буфер. Обработка во время записи теперь включена по умолчанию с сохранением явного выбора, но по-прежнему требует Index + Whisper; импорт и OPUS её не используют. Русские порядковые числительные теперь раскрываются перед Android Piper/MMS/Supertonic. [Проверки реализации и ограничения замеров](android/benchmarks/2026-10-17-streaming-cache/README.md).

**Предыдущая загрузка, 17 октября:** **iOS 1.0 (53) и Mac App Store 1.0 (71)** собраны из исправленных исходников, проверены и загружены в App Store Connect. Включены полная потоковая озвучка без потери фрагментов/повторов из-за пробелов, контекстные русские числительные и промежуточный вывод MLX на Mac. Оба пакета содержат 13 актуальных роликов. Проверки проекта: 143 PASS. Обработка Apple, установка через TestFlight и выбор сборок для ревью ещё не подтверждены. [Проверки и результат загрузки](publication/apple-speech-store-2026-10-17.md).

После завершённого сравнения настроек iPhone Index 9B сохраняет MTP с двумя черновыми токенами; экспериментальных переключателей окружения MTP/числа токенов/Q8-KV нет. Mac Index 9B по-прежнему использует MLX с промежуточным выводом. [Сравнение](benchmarks/ios-mt-options-2026-10-17/README.md).

На iPhone у `RecordingPreviewProbe` есть явно включаемый режим `OT_SPEECH_CORRECTNESS_PROBE`: он проверяет заданные длинные предложения/числительные и реальный Index 9B через штатный синтез и `SpeechPlayer`. Режим фиксирует завершения воспроизведения и синтетический PCM без записи в историю и переопределения настроек; очистка удаляет только его отдельный каталог результатов. [Порядок проверки и результаты](benchmarks/iphone-speech-correctness-2026-10-17/README.md).

На Apple `StreamedSpeechStart` хранит точный использованный префикс перевода и собирает все части `SpeechPreparation` перед воспроизведением предложения. При переписывании префикса ожидающая озвучка отменяется; после ожидания воспроизведения повторно проверяется отмена. Mac MLX передаёт накопленный текст принятых токенов через `kat_mlx_run_stream`; состояние callback отключается до возврата синхронного запроса. `RussianSpeechText` раскрывает неоднозначные окончания порядковых числительных только при поддержанном соседнем контексте (отдельные даты сохраняют прежнее правило). Уже прозвучавший текст нельзя отозвать, если модель его переписала. [Проверки реализации и ограничения](benchmarks/apple-speech-correctness-2026-10-17/README.md).

Android также предлагает `whisper-large-v3-turbo-q8_0` как явно выбираемый пакет распознавания в `android-asr.json`. Он использует тот же Whisper-бэкенд, языковые соответствия F16 и неизменные greedy-декодирование и выбор CPU-варианта. Размер и контрольная сумма upstream-пакета закреплены и проверяются. Q8 не заменяет F16 или маршруты Auto через GigaAM/Parakeet. [Сравнение вариантов](android/benchmarks/2026-10-17-whisper-options/README.md).

Android Whisper содержит две изолированные JNI-библиотеки: базовую `armv8-a` и дополнительную `armv8.2-a+dotprod+fp16`. Проверка HWCAP в базовом `kat_media` предшествует загрузке ускоренной библиотеки; несовместимый процессор или ошибка её загрузки оставляют базовый Whisper. Обе принимают выбранную модель F16 или Q8 с теми же четырьмя потоками, параметрами декодирования и исправлением отмены. `setup-media.sh` собирает обе; Gradle упаковывает ускоренную библиотеку без нативной зависимости при линковке. Apple и маршрутизация ASR Auto не изменены.

VITS на Android и Apple использует до четырёх потоков по числу доступных CPU; Supertonic сохраняет два потока. Android JNI возвращает замеры фаз без текста через `OfflineMedia.lastSpeechTiming`. Piper использует ограниченный кэш контекста; остальные движки голоса по-прежнему создаются на один вызов синтеза.

Карточки голосового режима Android всегда присутствуют, оригинал раскрыт. `TranslatorState.isTextPlaying` определяет активную карточку через наблюдаемое состояние воспроизведения; её действие останавливает звук до проверки занятости обработки. `TextPanel` показывает крестик во время воспроизведения и динамик в остальное время.

Android `kat_media` включает общий модуль `Privacy/InferencePrivacy.c`, который движок озвучки вызывает перед созданием голоса.

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

### Память Metal и аудио на iPhone (17 октября 2026)

До загрузки моделей `OfflineTranslatorApp.init` устанавливает `GGML_METAL_NO_RESIDENCY=1`. Иначе закреплённая версия ggml запрашивает постоянную резидентность Metal-буферов, расходуя системный лимит закреплённой памяти, необходимой CoreAudio. Модели остаются загруженными, вычисления продолжают использовать Metal; пользовательская настройка экономии памяти не меняется. Эта политика запуска iOS не меняет runtime macOS и Android. [Диагностика и проверки на устройстве](publication/ios-microphone-wired-memory-2026-10-17.md).

При предупреждении iOS о памяти `AppModel.memoryWarning` сначала вызывает `ConversationPipeline.relieveMemoryPressure`, чтобы освободить неиспользуемый распознаватель рядом с крупным переводчиком. Если обработка активна, освобождение ждёт границы распознавания/перевода/озвучки; повторные ожидающие предупреждения объединяются. Переводчик, результаты и готовность сохраняются. Готовность распознавания снимается; перед появлением следующего микрофона нужна подготовка. Пользовательская настройка не меняется. Прежняя полная выгрузка остаётся запасным вариантом, когда нет освобождаемого распознавателя, и для камеры.

Выпуск 1.0 (52) включает эти изменения и entitlement дополнительной памяти. Проверка магазинного пакета и приёмка TestFlight отдельно отражены в [отчёте выпуска](publication/ios-store-build52-2026-10-17.md).

### Комплект исходников и воспроизводимость SDK

`scripts/package-dependency-sources.py` создаёт проверенные части TAR с исходниками по списку разрешённых. `scripts/rebuild-opus-source-kit.py` пересобирает изолированный Opus XCFramework из проверенных архивов и патча, добавляет manifests по платформам и при необходимости подписывает SDK. Существующие результаты vendor он не заменяет. [Происхождение и ограничения](licensing/2026-10-14/publication-and-sdk.md). Общий ресурс уведомлений теперь содержит 46 документов, включая Wayu, Supertonic 3 и условия моделей CC BY-NC.

Подпись входных speech SDK: `scripts/sign-verified-speech-sdks.py` сверяет архивы и все исходные файлы, создаёт отдельные копии и подписывает их сертификатом дистрибьютора Kat. Подпись не называется подписью upstream; полезная нагрузка не меняется. Точные source commits и embedded ONNX описаны в `docs/licensing/2026-10-14/sdk-provenance.json`.
