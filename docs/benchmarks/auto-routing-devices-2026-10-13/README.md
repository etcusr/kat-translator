# Auto / OPUS: iPhone и Pixel — 13 октября 2026

Последующая проверка: [голос, микрофоны, Auto после ASR](../voice-auto-devices-2026-10-13/README.md). Ограничения ниже относятся к этому текстовому прогону.

Продолжение исправлений [fc2a3e7](../auto-routing-fixes-2026-10-13/README.md). Пользователь завершил резервное копирование iPhone, разрешил установить build45 и проверить исправления; затем отдельно разрешил установку и проверку Pixel. Удаление приложений, моделей или истории не выполнялось.

## Pixel 9 Pro

Установлена **Android 0.4.6/code21, Debug** поверх 0.4.5/code20. Новый номер отделяет артефакт с исправлениями от старого code20. SHA-256 APK: `1f0937878c09c2d0920db61f025ccd786ea6cc040496853ced00e89ba28cf70e`. Файл: `dist/android/kat-translator-0.4.6-debug.apk`.

`AutoRoutingRegressionTest.autoSwitchesNativeOwnershipPassesSameLanguageAndUsesManualDirections` прошёл на реальных установленных моделях через Compose-кнопки:

1. RU→EN — OPUS; DE→EN — Index 2B; RU→EN — снова OPUS. После каждого результата проверены фактические владельцы native-контекстов и leases: у неактивного движка они `null`, у активного — присутствуют.
2. Автоопределённый EN→EN вернул исходную фразу без ошибки отсутствующего OPUS-маршрута.
3. План RU↔DE использует установленные вручную `zle-de`/`de-zle`, не требует лишнюю 2B. RU→DE реально переведён через OPUS, результат содержит «Zug».
4. Выгрузка после прогона завершена. `UiTestEnvironment` восстановил настройки: все пары ключ/значение до и после совпадают. Перечни файлов истории и пакетов также совпадают; это контроль сохранения состава, не повторное хеширование всех весов.

Использована сохранённая классификация Pixel `weak`, DeviceProbe не подменялся. История тестовых фраз и автоматическая озвучка отключены. Gradle: `testDebugUnitTest`, `lintDebug`, `assembleDebug`, `assembleDebugAndroidTest` успешны; unit suite — 103 теста, 0 ошибок. Нативная device-проверка — 1 комплексный тест, 15,282 с; это длительность теста, не benchmark скорости моделей.

## iPhone 17 Pro

Установлена **iOS 0.5.15/build45**, версия подтверждена через CoreDevice. Первоначальный `list devices` показывал `disconnected`, но прямой `device info details` открыл соединение; после этого установка прошла. Этот случай не доказывает, что причиной прежней недоступности было резервное копирование.

**Три UI-теста прошли.** `testShortGreetingAutomaticLanguageOnPhone` (EN→RU, EN→EN, неопределённый короткий текст) и `testOpusDirectionsSelectionShowsTotal` (выбор/отмена направления, объём). Новый `testAutoOpusPickerAndDetectedTextSwitchingOnPhone` подтвердил доступность японского при активном OPUS/Auto и реальные переходы OPUS → Index 9B для немецкого → OPUS для русского. Проверены перевод с числом 07:45 и выбранная модель в штатном меню. На iPhone установлены OPUS и 9B; установленных 2B/отдельных направлений нет.

Для воспроизведения компактной ветки тест скрывает сохранённый DeviceProbe только в launch-domain; сохранённая аппаратная оценка не меняется. Auto включается настоящей кнопкой. В первых попытках исправлены недостатки нового теста: iOS-кнопка `sheet.done`, ожидание готовности и неверный строковый launch-аргумент `translationAuto=YES`. Последний не проходил `as? Bool` и оставлял ручной режим; это не ошибка рабочего переключателя Auto. Та же фикстура исправлена в Mac `testAutomaticTextKeepsSelectedTarget`, повторный Mac UI-прогон с реальным включением Auto прошёл. Код приложения build45 не менялся.

Перед тестами сохранены настройки. После тестов исходный plist восстановлен, приложение запущено без тестовых аргументов: все значения настроек совпали. Перечни также совпали: History — 12 записей файлов, Models — 372, TranslationPackages — 17. Это сверка состава, не новый хеш-аудит всех весов.

## Повторение и проверки репозитория

- iOS UI target `TranslatorUITests`: `testAutoOpusPickerAndDetectedTextSwitchingOnPhone`, `testShortGreetingAutomaticLanguageOnPhone`, `testOpusDirectionsSelectionShowsTotal`.
- Android instrumentation: `adb shell am instrument -w -e class org.openoffline.translator.android.AutoRoutingRegressionTest org.openoffline.translator.android.test/androidx.test.runner.AndroidJUnitRunner` (требует установленных OPUS, Index 2B и ручных RU↔DE-пакетов).
- Mac UI: `MacUITests/testAutomaticTextKeepsSelectedTarget` — новый успешный прогон после включения Auto через кнопку.
- `python3 -m unittest discover -s scripts/validation`: 98 тестов, 0 ошибок. `git diff --check` пройден.

## Доказательства и границы

Локальные raw-логи: `.build/iphone45-check/` и `.build/pixel-auto-check/`; xcresult в `.build/DerivedData/Logs/Test/`. Они исключены из Git: содержат пути подписи и идентификаторы устройств. В Git входят тесты и этот отчёт с синтетическими фразами.

Этот прогон не покрывает все языки, физическую сотовую загрузку и native BG→EN через zls-en: таких весов на устройствах нет. Фильтрация установленного группового маршрута проверена unit-тестами предыдущей задачи. ASR/preview-переключение после определения языка проверено в OfflineCore; этот телефонный прогон ориентирован на текстовый UI и реальные модели.
