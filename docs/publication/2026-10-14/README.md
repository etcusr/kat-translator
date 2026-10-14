# Подготовка iOS / macOS к публикации — 14 октября 2026

Статус: подготовка, **не отправлено в TestFlight или App Review**. Development-установка и проверка миграции описываются отдельно в [отчёте устройства](../../maintenance/ios-kat-migration-2026-10-14.md). Комплект от12 октября остаётся историческим; этот файл обновляет решение по идентификаторам, подписи и составу iOS-кандидата.

## Карточка и идентификаторы

В App Store Connect создана карточка **Kat translator** для iOS и macOS; обе платформы имеют черновую версию 1.0 в Prepare for Submission. Создание карточки не означает загрузку или публикацию сборки.

Общий ID карточки — `app.kattranslator`. iOS extension — `app.kattranslator.downloads`; отдельной карточки приложения для расширения нет. Рекомендованный SKU общей карточки — `kattranslator`; фактически сохранённый SKU по снимку после создания не виден. Для магазина Mac потребуется сборка с тем же Bundle ID; текущий Mac остаётся `org.openoffline.translator.mac`.

## Ранее экспортированный iOS-кандидат

- Версия **0.5.16 / build46**, iOS18+, iPhone ARM64. Сборка содержит новый ID и `kattranslator://downloads`, чтобы Live Activity новой версии не открывала старую app с `openoffline://downloads`.
- Этот экспорт выполнен до последующих правок текста конфиденциальности и ES/TR; он не представляет текущий код. Перед отправкой нужен свежий архив. Release archive успешен. Финальный App Store export с `destination=export` успешен; загрузка не выполнялась.
- App и extension имеют **explicit distribution-профили**: `app.kattranslator` / `app.kattranslator.downloads`. Xcode подготовил их автоматически при export. Изначальная development-подпись wildcard больше не является препятствием для distribution.
- `codesign --verify --deep --strict` обеих частей успешен. В distribution нет `get-task-allow` и списка ProvisionedDevices; increased-memory-limit сохранён в приложении. Срок профилей: 13.10.2027 22:17:56 UTC.
- App Store IPA: `dist/ios/store-candidates/Kat-translator-0.5.16-build46.ipa` (ignored). Это технически экспортированный кандидат с открытыми пунктами ниже, а не одобренная магазином поставка.
- Development app для телефона: `dist/ios/Kat-translator-0.5.16-build46.app` (ignored). Эти два артефакта имеют разные назначения и подписи.

IPA: 70739147 байт; SHA-256 `65cb06d640ee26519a848df089bf10d6c903c7f307ba3849f66165553ac8165a`.

Локальные доказательства: `.build/kat-id-migration-2026-10-14/`: `archive-privacy.log`, `export-final.log`, `Kat46-privacy.xcarchive`, `distribution-final.json`, `artifact-audit.json`. Не добавлять raw-логи в Git: они содержат локальные сведения подписи.

## Конфиденциальность: что сделано и что открыто

В ранее экспортированном IPA проверено наличие `PrivacyInfo.xcprivacy` приложения. Собственный код использует:

| Категория | Причины Apple | Фактическое назначение |
|---|---|---|
| UserDefaults | CA92.1 | Собственные настройки приложения |
| FileTimestamp | C617.1 | Метаданные файлов своего контейнера, integrity-cache и очистка временных файлов |
| SystemBootTime | 35F9.1 | Таймеры записи и интервалы обработки |
| DiskSpace | E174.1, 85F4.1 | Проверка места перед загрузкой и показ хранилища пользователю |

Декларации: tracking=false, tracking domains и collected data types пустые. Это декларация текущего приложения с локальной обработкой и без собственной аналитики; она не заменяет проверку условий хостингов загрузок, деклараций SDK и App Privacy в кабинете. Официальные причины проверены14.10 по [Apple required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) и [категориям API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Генератор теперь включает `.xcprivacy` в ресурсы iOS. Mac ресурс не добавлялся автоматически.

**Обновление:** пять отдельных framework manifests добавлены и включены в свежий Release archive; шесть деклараций и подписи проверены. [Отчёт](../privacy-frameworks-2026-10-14.md). Ниже — исходные наблюдения старого IPA, не состояние нового архива.

В проверенном историческом IPA только один privacy manifest. Сканирование импортируемых символов показывает **кандидатов для отдельной проверки** в пяти frameworks без собственных manifest:

- `Python.framework`: fstat, fstatfs, lstat, mach_absolute_time, stat, statfs;
- `TranslationRuntime.framework`: fstat, stat;
- `OmniVoiceRuntime.framework`: fstat;
- `_hashlib.framework`, `_ssl.framework`: fstat, stat.

Повторная сверка сохранённой development-сборки `dist/ios/Kat-translator-0.5.16-build46.app` 14.10 подтверждает один manifest приложения и отсутствие отдельных manifest у этих пяти frameworks. В `_ssl` найдена строка OpenSSL 3.0.18. OpenSSL входит в [список SDK Apple](https://developer.apple.com/support/third-party-SDK-requirements/), включающий переупакованные SDK; требования к его упаковке и подписи также требуют проверки.

Наличие импортируемого символа не доказывает путь выполнения или нарушение; требуется проверить назначение вызовов и добавить подходящие декларации/обновить упаковку. Не копировать manifest приложения во все библиотеки без такой проверки. Условия Apple требуют деклараций для соответствующих bundles, а не обещания общей декларацией покрыть всё.

Политика RU/EN опубликована: https://etcusr.github.io/kat-translator/privacy/; исходник — `site/privacy/index.html`, контакт — **katlabs.dev@gmail.com**. Главная страница https://etcusr.github.io/kat-translator/ содержит контакт поддержки. Deployment и HTTP 200 без авторизации проверены. Остаются проверка App Privacy и экспортных деклараций. [Текущая сверка конфиденциальности](../privacy-audit-2026-10-14.md).

## Лицензии и атрибуции

Предыдущий [аудит](../../licensing/2026-10-12/README.md) остаётся действующим списком вопросов. В новом executable найдены строки `Failed to initialize espeak-ng` и `PiperPhonemizeLexicon`: смена подписи не исключила GPL-зависимость. Собственный код переведён на GPL-3.0-or-later; eSpeak сохранён. Нельзя обещать, что бесплатность, открытие собственного кода или удаление одного голоса автоматически закрывают условия App Store и всех зависимостей.

Denis и остальные текущие голоса сохранены в каталоге. Прямой запрет не установлен; неопределённость происхождения и прав описана в [проверке голосов](../../licensing/2026-10-14/voice-alternatives.md). NC/OpenRAIL и атрибуции проверяются отдельно по моделям; автоматического запрета только из-за бесплатной публичной поставки здесь не утверждается.

В архиве обнаружены семь файлов notices/licenses, но это **не полный комплект** условий всех runtime и моделей. Сборочный аудит не заменяет инвентаризацию и доступность соответствующих исходников, если они требуются. Не отправлять IPA внешним тестировщикам/в публичный выпуск, объявляя эти вопросы решёнными.

## Карточка и материалы

Обновлены [RU](ios/ru/description.txt) / [EN](ios/en/description.txt) тексты iOS: Auto, Index2B/9B и OPUS-направления; не обещается скачивание всех54 пакетов. Поля name/subtitle/keywords/promotional/description/whats-new проверены по лимитам длины. Это файлы для заполнения карточки, они ещё не отправлены в App Store Connect. Итоговый отбор голосов может потребовать корректировки текста.

Подготовлены четыре Mac-скриншота установленной версии 0.6.7: перевод, голос, модели и языки (`dist/store/macos-0.6.7-ru/1440x900`, локально). Вариант 2880×1800 увеличен из оригиналов, не является нативным Retina-снимком. Их соответствие окончательной Mac-сборке и загрузка в кабинет не подтверждены.

Дальше нужны iPhone-скриншоты окончательной сборки, возрастная анкета, privacy/export compliance и данные ревьюера. DSA и Free Apps Agreement имеют статус Active; платное соглашение для текущего бесплатного выпуска не оформляется. Территории распространения ещё не изменены.

## macOS

Платформа добавлена пользователем в общую карточку. Существующий Mac DMG не готов для Mac App Store: текущий генератор задаёт прежний Bundle ID, `ENABLE_APP_SANDBOX=NO`, manual/ad-hoc build settings и hardened runtime=NO. Нужны отдельный магазинный профиль сборки, перенос ID/настроек, sandbox-проверка файлов/микрофона/горячих клавиш и Python workers, подпись и runtime-приёмка. Mac app/DMG и его данные в этой задаче не заменялись.

[Apple: несколько платформ в карточке](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/) · [создание карточки](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
