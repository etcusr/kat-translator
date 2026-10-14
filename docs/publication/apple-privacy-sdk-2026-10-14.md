# App Privacy и SDK: iOS / native Mac — 14 октября 2026

Проверка относится к новым локальным сборкам iOS **1.0 (49)** и Mac App Store **1.0 (68)**. iOS48/Mac67 — прежние лицензионные пакеты; для дальнейшей доставки подготовлены новые проверенные пакеты. Это аудит интеграции и упаковки, не подтверждение App Review и не изменение ответов в кабинете.

**Продолжение:** [сторонние загрузки и ответы App Privacy](model-download-privacy-2026-10-14.md). Хостинговая классификация ниже была открытой на момент сборки49/68; теперь подготовлены ответы, новая RU/EN policy и app manifests. Готовые49/68 сохранены; их заменяют [проверенные50/69](hosting-manifests-release-2026-10-14.md) с актуальными app manifests. App Privacy опубликован по снимку кабинета.

## Найдено и исправлено

1. **Mac ONNX 1.30 содержит включаемую по умолчанию 1DS-телеметрию.** В бинарнике найдены `PosixTelemetry`, Microsoft OneCollector и флаг `ORT_DISABLE_TELEMETRY`. По исходникам именно v1.30.0 `DisableTelemetryEvents` не предотвращает начальное событие ProcessInfo. Прежние вызовы в OCR/Wayu после CreateEnv недостаточны; наличие/отсутствие OpenSSL к этому не относится. Сетевую отправку старой сборки этим исследованием не наблюдали.
2. **Добавлен запрет до инициализации.** `InferencePrivacy.c` один раз устанавливает `ORT_DISABLE_TELEMETRY=1`, включая случай внешнего значения `0`. Все шесть входов OCR/Wayu/Piper/Supertonic/VAD/Omnilingual проходят проверку до обращения к ONNX/Sherpa. Ошибка установки запрещает запуск SDK. Реальная Mac-библиотека после CreateEnv: `disabled=1`, logger и LogManager не созданы. Проверка выполнена без CI-флагов, в отдельном процессе с запрещённой сетью. Это не перехват всего трафика приложения.
3. **Пропущенные manifests.** Abseil/Protobuf подтверждены в реальных бинарниках: iOS main и OpusRuntime; Mac ONNX/Sherpa/OpusRuntime, две копии SentencePiece, Protobuf/upb и PyTorch. Добавлены декларации для этих интеграций. `cabsl`/`fabsl` в NumPy и текст подсказки `LLAMA_OPENSSL` не засчитывались как сторонние SDK.
4. **Swift-пакеты.** FluidAudio получил свою декларацию файловых API в существующем resource bundle; OfflineCore — ресурс времени выполнения и настроек. У приложения и каждого SDK отдельный файл; имена не перетираются при копировании.
5. **Подпись после упаковки.** Изменённый OpusRuntime повторно подписывается. Codeless bundles имеют собственные идентификаторы, без executable/NSServices и устаревшей подписи ресурсов. Vendor-файлы не изменены. Ошибка подписи, отсутствующий SDK или новая конфликтующая upstream-декларация прерывает сборку.

Подробная карта библиотек, причин API и путей — [Dependencies/privacy/README.md](../../Dependencies/privacy/README.md). В iOS девять manifests; в Mac также девять, но наборы различаются. Требование к required-reason API Apple не распространяет на native macOS; это не отменяет требований к данным и перечисленным SDK. Не переносить iOS-причины в Mac только ради одинаковых списков.

## App Privacy: что подтверждено и что ещё нельзя утверждать

| Данные / действие | Проверенный путь | Вывод для подготовки анкеты |
|---|---|---|
| Текст, голос, изображения, переводы | Локальные ASR/MT/TTS/OCR; локальная история, системный Share по действию пользователя | Автоматической передачи этого содержимого разработчику или серверам моделей в проверенных путях нет |
| Аналитика/реклама/tracking | В Apple target нет Firebase, рекламного SDK, аналитического backend или IDFA-пути; ONNX подавлен до запуска | Не добавлять Android ML Kit к Apple-декларации. Для нового состава не заявлен tracking |
| Python/HF | Index задаёт offline + disable-telemetry до импорта; OPUS — offline до импорта, local_files_only; упакованный HF telemetry helper сразу возвращает в offline-режиме | Наличие networking-модулей не равно их вызову; в этих путях сетевые модели/телеметрия не используются |
| FluidAudio | `AsrModels.loadLocal`, затем локальная ASR | Download convenience API SDK не используется данным путём |
| Загрузка пакетов | URLSession, URL из каталога, HTTPS GET/Range; текст/запись/результат не включаются в запрос | Хостинг получает адрес соединения, запрошенный файл и технические заголовки. Это отдельный вопрос от локального inference |
| Поддержка/ссылки/экспорт | Пользователь открывает внешний браузер/почту/Share; автоматической формы загрузки содержимого нет | Не считать любую добровольную переписку автоматическим сбором приложения; учитывать конкретный способ отправки |

**Общий ответ «No, we do not collect data» ещё нельзя считать окончательно подтверждённым только по manifests.** Политики [Hugging Face](https://huggingface.co/privacy) и [GitHub](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) описывают технические сведения/журналы. Hugging Face прямо указывает IP, сведения сессии/устройства и хранение для работы/безопасности сервиса. Публичный текст не доказывает отсутствие хранения для анонимных model-download/CDN запросов. Осталось установить применимые к этим запросам категории, цели и связь с пользователем; при наличии сбора партнёром отразить его в App Privacy и app manifest. Не подставлять «не связан» или «только функциональность» без основания и не приписывать приложению все категории веб-аккаунта хостинга.

SDK manifests описывают отключённую телеметрию и локальную работу конкретных библиотек; App Privacy охватывает всю интеграцию, включая внешние сервисы. Политика уже раскрывает сторонние технические запросы: https://etcusr.github.io/kat-translator/privacy/. Новых ответов в App Store Connect в этой задаче не сохраняли.

## SDK signatures: отдельный незакрытый пункт

Проверенные входные `OpusRuntime.xcframework`, iOS ONNX/Sherpa и Mac Sherpa XCFramework **не имеют внешней подписи пакета SDK**. Подпись готового приложения и встроенных бинарников проверяется отдельно и не выдаётся за подпись поставщика. Нужно подтвердить допустимый путь поставки этих repackaged SDK: подписанные upstream-пакеты либо воспроизводимая собственная сборка и подпись SDK с зафиксированным происхождением. Не закрывать это наличием notices или нашей повторной подписью внутри app. Принятие Apple новой структуры resource bundles также ещё не подтверждено.

Неиспользуемые Python `statfs/fstatfs` в iOS остаются известным ограничением: реальные вызовы Wayu не найдены, вымышленная disk-space причина не добавлена. Если обработка Apple выдаст замечание, нужен разбор вызова/пересборка Python с исключением API.

## Проверки

- Регрессия ранней инициализации воспроизведена: 18 сценариев шести entry points падали до правки. После правки два теста со всеми сценариями проходят, включая повторный вызов и ошибку setenv.
- Проверки installers покрывают missing SDK, конфликт upstream, повторную установку, место manifest, codeless bundles, copy-before-sign и отказ подписи; обнаружена и исправлена устаревшая подпись resource bundle в обычной Mac-упаковке.
- Реальный ONNX: `python3 scripts/validation/check_onnx_telemetry.py <libonnxruntime.dylib>` — PASS. Скрипт считывает состояние provider по символам закреплённого бинарника; при изменении символов требует повторной проверки.
- Архивы и экспорт iOS49/Mac68 — PASS. В каждом конечном пакете девять manifests; побайтовая сверка с исходными декларациями и 42 notices прошла. Все 72/154 Mach-O имеют строгую подпись и тот же leaf-сертификат, что приложение; distribution-профили соответствуют app/widget, не debug и не просрочены. Mac installer имеет сертификат 3rd Party Mac Developer Installer. Сохранены sandbox, оба helper, уникальные unsigned codeless bundles; внешних нестандартных путей зависимостей нет.
- В пакетах нет найденных OpenSSL/rustls/BoringSSL, XCTest и one-beer; 14 анимаций совпадают с исходниками. ITSAppUsesNonExemptEncryption=false на обеих платформах.
- Shell-фаза iOS теперь останавливается при отказе первого installer; регрессия проверяется запуском реального shell-текста с отказом первой команды. Окончательный архив/экспорт повторён после исправления.
- Полный Python-прогон: **132 теста, PASS**. Проверка 72 полей восьми локализаций и двух Notes — PASS. Это не повтор полного native runtime/устройства/TestFlight.

Первый прогон выявил два расхождения документации/snapshot проекта; номер iOS синхронизирован, в snapshot добавлен только новый C-файл. Итоговый полный прогон выше включает новую регрессию shell-фазы. Подробные локальные логи — `.build/privacy-sdk-2026-10-14/`; личные сведения подписей/устройств в отчёт не включены.

## Конечные артефакты

Пакеты с SHA-256 sidecar лежат в `dist/ios/store/Kat-translator-1.0-build49.ipa` и `dist/macos/store/Kat-translator-1.0-build68.pkg`. Машиночитаемый [результат](apple-privacy-sdk-2026-10-14.json) содержит хэши, состав manifests и границы проверки. Store-пакеты не загружались и не устанавливались. Проверочная development49 установлена для съёмки; после системного подтверждения XCTest четырёхъязычный сценарий прошёл, 16 кадров готовы. [Скриншоты](localized-screenshots-2026-10-14.md) и [готовые тексты](2026-10-14/LOCALIZATIONS.md) учитываются отдельно.

## Официальные основания

- [Apple: SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) — listed SDK, repackaging и binary signatures.
- [Apple: privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) и [размещение](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) — платформы и расположение ресурсов.
- [Apple: required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) — SDK не заменяет свою декларацию декларацией приложения.
- [Apple: App Privacy](https://developer.apple.com/app-store/app-privacy-details/) — сбор партнёрами, удержание дольше обслуживания запроса, категории по назначению IP, ответственность за актуальные ответы.
- [ONNX 1.30 privacy](https://github.com/microsoft/onnxruntime/blob/v1.30.0/docs/Privacy.md) и [PosixTelemetry](https://github.com/microsoft/onnxruntime/blob/v1.30.0/onnxruntime/core/platform/posix/telemetry.cc) — источник исправления.
