# Голос и Auto на iPhone / Pixel — 13 октября 2026

Продолжение [текстовой приёмки](../auto-routing-devices-2026-10-13/README.md), исходный коммит `3af52b3`. Проверяются iOS **0.5.15 (45)** и Android **0.4.6 (21)**. Production-код и номера выпусков не менялись; добавлены opt-in тесты физических устройств. Временный iPhone host собран с `ENABLE_TESTABILITY`; после проверки возвращена обычная сохранённая build45.

## Что именно проверяется

Синтетические RU/DE-фразы из уже поставляемых `sherpa-onnx-supertonic-3-tts-int8-2026-05-11-{ru,de}.m4a`: приветствие, «так звучит мой голос», поезд в пять часов. В тестах работают настоящие установленные ASR, MT, TTS и плееры. Текст распознавания не подставляется. На телефонах используются собственные динамики: Mac подключён к наушникам, поэтому один телефон воспроизводит образец, второй записывает его.

- **iPhone:** Whisper определяет RU/DE без языковой подсказки. Production `PackageDownloadCoordinator.translationResolver` выбирает модель после ASR. Для проверки обеих веток Auto тест временно скрывает DeviceProbe в process-local argument domain; сохранённая оценка устройства не изменяется. Установлены OPUS и Index 9B, поэтому fallback проверяется на 9B, не 2B.
- **Pixel:** исходный язык голоса выбирается явно. ASR Auto выбирает GigaAM для RU и Parakeet для DE; это **не автоматическое определение неизвестного языка речи**. `finishTranslation` получает язык результата ASR, после чего Auto MT выбирает OPUS или Index 2B. Используется сохранённый класс Pixel `weak`.

## Результаты

| Устройство / путь | Проверки | Результат |
|---|---|---|
| Pixel, импорт M4A через `TranslatorState.importAudio` | RU/GigaAM → OPUS; DE/Parakeet → 2B; RU/GigaAM → OPUS; исходная запись, перевод, настоящий TTS/воспроизведение; освобождение неактивных native-движков и leases | 1 комплексный тест прошёл |
| iPhone, PCM из M4A в production `runRecording` | Без подсказки RU → OPUS, DE → 9B, RU → OPUS; язык, модель в метриках, перевод, исходная запись, TTS и непустой аудиофайл | Повтор той же сборки и окончательный прогон прошли; первый сбой озвучки описан ниже |
| iPhone, preview до завершения записи | Начальная 9B, распознан русский, resolver переключает на OPUS; previewBlocks > 0, `during-recording`, итог без повторной подстановки текста | Прошёл на реальных моделях |
| iPhone, физический микрофон ← динамик Pixel | Немецкий без подсказки → 9B; следующий русский → OPUS; реальные AudioRecorder, VAD, ASR, MT | Прошёл |
| Pixel, физический микрофон ← динамик iPhone | RU → DE → RU, production begin/finishRecording, ASR Auto и MT Auto, озвучка | 1 комплексный тест прошёл |

iPhone hosted-тест вызывает production AudioRecorder/ConversationPipeline, а не кнопку UI. Android instrumentation вызывает production TranslatorState в Activity. Это аппаратные интеграционные проверки; покрытие нажатий/раскладки и предыдущие текстовые UI-тесты описаны отдельно. При физической записи окно захвата — 25 секунд, аудиообразец короче; это не тест скорости модели.

## Наблюдения, которые нельзя скрывать успешным повтором

1. Первый iPhone прогон корректно распознал и перевёл немецкую фразу на Index, но запуск озвучки завершился `com.apple.coreaudio.avfaudio 1852797029` (`AURemoteIO StartIO`). Повтор **той же сборки без изменения кода** прошёл полностью. Причина единичного сбоя не установлена; он не объявлен исправленным. В окончательной тестовой оболочке исправлено разбиение аргументов отключения автозагрузки и на время теста отключён автосон, как в других opt-in probes. Это устраняет неоднозначность окружения, но не доказывает причину исходной ошибки.
2. При первой записи немецкого образца микрофоном iPhone Whisper добавил завершающее «Hallo.» после правильного текста; перевод содержит дополнительное «Hello.». В файловом контроле этой добавки не было. Захват включает длительную тишину; причина не локализована. Язык и модель определены правильно, но точное качество транскрипции не считается безусловно пройденным.
3. Android не предлагает source=Auto в Voice. Проверка автоматического определения произвольного языка речи на Pixel невозможна в текущем продукте; подтверждён выбор моделей по явно выбранному/возвращённому ASR языку. Preview Android с Auto GigaAM/Parakeet не поддерживается (нужен Whisper и совместимая MT); iPhone preview проверен отдельно.

## Воспроизведение

- Android: `VoiceAutoRoutingTest#importedSpeechSwitchesRealAsrAndAutoTranslation` и `#microphoneSpeechSwitchesRealAsrAndAutoTranslation`. Требуются установленные GigaAM, Parakeet, OPUS, Index 2B, английский голос; `UiTestEnvironment` восстанавливает настройки. Для микрофона разрешение RECORD_AUDIO должно быть выдано, а instrumentation-аргумент `-e voicePeer 1` явно включает координированный микрофонный тест; без него тест пропускается. Пример: `adb shell am instrument -w -e class org.openoffline.translator.android.VoiceAutoRoutingTest#importedSpeechSwitchesRealAsrAndAutoTranslation org.openoffline.translator.android.test/androidx.test.runner.AndroidJUnitRunner`.
- iPhone: `KAT_VOICE_AUTO_TEST_BUILD=1 python3 scripts/generate-project.py`, затем `xcodebuild... -only-testing:ArticleRuntimeTests/VoiceAutoRoutingIntegrationTests/<method> test`. Методы: `testAfterStopDetectsLanguageAndSwitchesAutoModels`, `testPreviewResolvesActualLanguageBeforeTranslation`, `testMicrophoneDetectsPeerSpeechAndSwitchesAutoModels`, служебный `testSpeakerForPixelMicrophone`. ASR/MT/TTS — из установленных пакетов; audio fixtures — из bundle приложения. По окончании выполнить обычный `python3 scripts/generate-project.py`; специальный target не должен входить в обычный проект/выпуск.
- Для микрофона iPhone дождаться `KAT_IPHONE_MIC_READY de/ru`, затем запустить на Pixel `PeerVoiceSpeakerTest` с instrumentation-аргументом `-e language de/ru`. Не воспроизводить образец до начала записи.
- Для микрофона Pixel запустить iPhone `testSpeakerForPixelMicrophone`; после `KAT_IPHONE_SPEAKER_READY` запустить Android microphone test. На каждый `KAT_PIXEL_MIC_READY <n> <language>` скопировать файл только с `ru`/`de` в контейнер iPhone `Documents/KatVoicePeerTest/<n>.txt`. iPhone воспроизводит соответствующий встроенный образец и удаляет временный каталог после трёх фраз.

## Доказательства и сохранность

Локальные raw-логи и снимки настроек: `.build/voice-auto-check/`, xcresult: `.build/DerivedData/Logs/Test/`. Они не входят в Git. Сырые микрофонные записи не экспортируются; история тестов отключена, iPhone pipeline не имеет history archive. В Git — только исходники тестов, generator opt-in и документация. Перед тестами сохранены настройки и перечни моделей/истории. После восстановления обычной iPhone45 и запуска без тестовых аргументов **все значения настроек обоих телефонов совпали**. iPhone: перечни History 12→12, Models 372→372, TranslationPackages 17→17; Pixel: файлы history 10→10, packages 807→807, состав совпадает. Это контроль состава, не новый хеш-аудит весов. Оба приложения открыты в обычном режиме.

Окончательная сборка Android instrumentation успешна; после добавления opt-in-проверок отдельно подтверждён пропуск микрофона/динамика без разрешающих аргументов. Содержимое микрофонного теста прошло до добавления этого предохранителя; новый контроль не считается повторным аппаратным прогоном. Gradle `testDebugUnitTest lintDebug` завершился успешно (103 unit в отчётах, 0 ошибок; неизменённые unit-задачи используют Gradle up-to-date). После восстановления обычного iOS-проекта — 98 validation, 0 ошибок; `git diff --check` пройден. Номера версий и сохранённые release-артефакты не изменены.

Основные логи: `pixel-fixtures.log`, `pixel-microphone.log`, `ios-fixtures.log` (первый сбой), `ios-fixtures-repeat.log` (успех той же сборки), `ios-fixtures-final.log` (2 теста успешно), `ios-microphone.log`, `ios-peer-speaker.log`, `restore-and-verify-final.log`. Все находятся в локальном каталоге доказательств выше.

Полная языковая приёмка, шумные помещения, Bluetooth-микрофон/смена маршрута, телефонные звонки/прерывания и фоновая работа этой серией не подтверждены.
