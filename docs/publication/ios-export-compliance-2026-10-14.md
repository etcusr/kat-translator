# iOS: декларация об освобождённом шифровании

14 октября 2026. iOS 0.5.16/build46; версия не повышалась.

В `apps/ios/Info.plist` добавлен `ITSAppUsesNonExemptEncryption` со значением **Boolean false**. Генератор проекта использует этот файл напрямую (`GENERATE_INFOPLIST_FILE = NO`), поэтому отдельное изменение генератора не требуется.

## Основание и анкета

После [удаления OpenSSL](ios-openssl-removal-2026-10-14.md) HTTPS-загрузки выполняются через Foundation URLSession; собственных реализаций шифрования приложение не поставляет. SHA-256 для проверки моделей не шифрует пользовательские данные. [Проверка на iPhone](ios-openssl-device-2026-10-14.md) подтвердила работу загрузок и голосовых сценариев без удалённых модулей.

Apple указывает, что для шифрования, ограниченного средствами операционной системы Apple, документы в App Store Connect не требуются, включая французскую декларацию: [таблица требований](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption). Значение false означает отсутствие **неосвобождённого** шифрования, а не отсутствие защищённых HTTPS-соединений.

- Форму **App Information → App Encryption Documentation → Upload** заполнять не требуется.
- Если у загруженной сборки появилась **Missing Compliance → Manage**, ответы должны соответствовать использованию только шифрования ОС; в перечне собственных/сторонних алгоритмов подходит **None of the algorithms mentioned above**.
- С этим ключом повторная анкета обычно не требуется. [Инструкция Apple](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).
- Доступность во Франции можно сохранить. Настройки стран и анкета на сайте в этой задаче не изменялись.

## Проверка и границы

Проверено на свежей обычной Release-сборке для `generic/platform=iOS`:

- `xcodebuild build` — **BUILD SUCCEEDED**; 0.5.16/build46.
- В готовом `OfflineTranslator.app/Info.plist` ключ присутствует и имеет тип Boolean со значением false, а не строку `NO`.
- `codesign --verify --deep --strict` — успешно; тестовых bundles нет.
- `check_ios_openssl.py` — проверены 72 Mach-O-файла, известных маркеров OpenSSL и зависимостей libssl/libcrypto нет; пять встроенных хеш-модулей сохранены.
- `plutil -lint` — успешно; существующие проверки документации/структуры — 10 тестов без ошибок.

Локальные логи: `.build/ios-export-compliance-2026-10-14/` (вне Git).

Это изменение только декларации iOS. macOS имеет отдельный состав runtime и требует отдельной проверки. Установка на устройства, новый IPA export, загрузка в App Store Connect и проверка Apple в эту задачу не входят. Предыдущие результаты тестов устройства не выдаются за новый прогон. Сохранённые `dist` и установленное приложение не заменяются.
