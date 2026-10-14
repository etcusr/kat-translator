# iOS: новая команда подписи и ID Kat — 14 октября 2026

## Решение и результат

Пользователь сменил Apple Developer account в Xcode и выбрал `app.kattranslator`. Прежний основной ID — `org.openoffline.translator.prototype`, расширение — `org.openoffline.translator.prototype.downloads`.

Текущие ID в `scripts/generate-project.py`:

| Target | Bundle ID |
|---|---|
| OfflineTranslator | `app.kattranslator` |
| DownloadActivityExtension | `app.kattranslator.downloads` |
| OfflineTranslatorUITests | `app.kattranslator.uitests` |
| Opt-in ArticleRuntimeTests | `app.kattranslator.articletests` |

Команда выбрана в ignored `apps/ios/Config/Signing.local.xcconfig`. Xcode показывает Individual team с `isFreeProvisioningTeam=False`. Имя владельца, Team ID, идентификатор iPhone и сертификаты не включены в Git. Android application ID и основной Mac bundle ID не менялись; Mac-проект регенерирован из общей основы (изменились только неиспользуемые в Mac iOS-target settings).

## Проверено

- Xcode Release build для подключённого iPhone, с `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`: **BUILD SUCCEEDED**. Это сборка, без install/launch/test.
- Приложение: точный development-профиль `app.kattranslator`, новая команда, подключённый iPhone в списке разрешённых устройств. Срок профиля: **2027-10-13 22:18:01 UTC** (14.10.2027 01:18:01 Europe/Moscow).
- Расширение: фактическая подпись `app.kattranslator.downloads`; Xcode использовал wildcard development-профиль этой команды. Срок: **2027-10-13 22:07:54 UTC**. Успех development-сборки не доказывает регистрацию отдельного explicit ID расширения для distribution.
- `codesign --verify --deep --strict` приложения и расширения успешен. Подписи сопоставлены с разрешениями профилей, включая wildcard; `com.apple.developer.kernel.increased-memory-limit` сохранён у приложения и разрешён профилем. Это development-подпись (`get-task-allow`), не App Store archive.
- 98 проверок `python3 -m unittest discover -s scripts/validation -p 'test_*.py'`: OK.
- Отдельная копия кандидата сохранена через `ditto` в `dist/ios/signing-candidates/Kat-translator-0.5.15-build45-kat-id.app`, повторная строгая проверка подписи успешна. Версия 0.5.15/build45 сохранена: это кандидат смены подписи/ID, а не установленный новый выпуск.

Raw-логи и локальные сведения: `.build/signing-2026-10-14/`, включая `build-kat.log`, `kat-verification.json`, `validation-kat.log`; они ignored. Первые пробы касались прежнего основного ID и временного суффикса `.downloadactivity`; это не действующая конфигурация. Эти пробы не устанавливались; наличие отдельного зарегистрированного ID расширения по wildcard-профилю не выводить.

## Связанные изменения

Служебные `run-asr-comparison.py` и `transfer-cached-voices.py` используют новый ID по умолчанию и принимают `--bundle-id`. Для старого установленного приложения явно передавать `--bundle-id org.openoffline.translator.prototype`.

Xcode создал `apps/ios/build/XCBuildData` с машинными данными. Папка исключена из Git и обхода ресурсов генератором: её JSON не должен попадать в bundle. Содержимое сохранено локально.

## Старое приложение и дальнейшие действия

На iPhone остаётся прежняя build45 с прежним ID и профилем до 20.10.2026. Новая подпись не продлевает срок уже установленной версии. Приложение не удалялось, данные/настройки/модели устройства в этой задаче не изменялись. Новое имя bundle означает отдельный контейнер: перед использованием подготовить проверенный перенос моделей, истории и настроек; старое приложение сохранять до проверки переноса.

Локальная старая копия `dist/ios/Kat-translator-0.5.15-build45.app` теперь **не проходит** строгую проверку: `a sealed resource is missing or invalid`, изменённые вложенные Python frameworks (например `_md5`, `_socket`, `_csv`). Причина и момент изменения не установлены; с новой сборкой у проверенного бинарника разные inode и link count=1. Копия не заменялась и не переустанавливалась; не использовать её для отката без восстановления подписи. Это не проверка целостности установленного приложения. Прежний отчёт об успешной установке остаётся историческим фактом.

Далее: установить кандидат отдельно и перенести данные с проверкой, повторить запуск/голос/Live Activity на телефоне. Для TestFlight создать запись приложения с новым основным ID в App Store Connect, подготовить archive/distribution с explicit ID расширения и проверить перед загрузкой. В этой задаче App Store Connect, upload, TestFlight и публикация не выполнялись. Mac Developer ID/notarization — отдельная задача.

Официальные инструкции: [automatic signing](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html), [создание записи приложения](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/), [загрузка сборок](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
