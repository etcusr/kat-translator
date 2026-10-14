# Публикация: что готово и что осталось

12.10.2026. Это практический список для владельца релиза, не заключение о соответствии магазинам. Правила магазинов проверены по официальным страницам; окончательная форма зависит от аккаунта и выбранного релиза.

## Уже подготовлено

RU/EN название, subtitle/short description, promotional text, keywords, полные описания для iPhone, Android и Mac; privacy/support/review notes; гайдлайн и реестр моделей; медиа с происхождением; учебное видео и субтитры. Заполненность и ограничения полей — `../evidence/metadata-lengths.json`.

## Решения издателя

- Имя/юридическое лицо, copyright, email поддержки, публичные HTTPS support/privacy URL пока **не выбраны пользователем**. Пустые значения сохранены в `../templates/publisher.json`.
- Цена, покупки/подписки, страны, категории, возрастная аудитория и рейтинг не утверждены. Предлагаемые категории: Apple Reference либо Travel; Google Tools либо Travel & Local — выбрать по позиционированию и доступным пунктам консоли.
- Проверить имя Kat translator и права на знак; ресурс в репозитории не доказывает отсутствие конфликта товарного знака.
- Заполнить сведения аккаунта, договоры, контакты ревьюера, необходимые декларации экспортного контроля/региональные сведения. Не ставить вымышленные данные и не выбирать возрастной рейтинг догадкой.

## Реальные технические блокеры

| Область | Наблюдение | Действие до отправки |
|---|---|---|
| Android release | В отчёте текущий артефакт `debug.apk` | Собрать release AAB с ключом издателя, проверить подпись/установку и путь обновления |
| Mac App Store | В `apps/macos/KatMac.entitlements` только audio-input, App Sandbox отсутствует | Отдельно спроектировать и проверить store target/sandbox, файлы, хоткеи, захват и Python helpers; существующий DMG не подавать как MAS-готовый |
| iOS submission | Установка developer build подтверждена, App Store archive/validation здесь нет | Создать distribution archive, проверить provisioning, capabilities, symbols и validation в Connect |
| Privacy-текст | `shared/apple/Settings/PrivacyView.swift` говорит, что оригинальная запись не сохраняется, хотя история её сохраняет при включённой опции | Исправить RU/EN текст и повторно сверить поведение перед выпуском |
| Voice licensing | MMS/OmniVoice и часть Piper имеют NC/другие ограничения; у некоторых голосов условия отсылают к отдельным файлам | Выбрать разрешённый состав, получить необходимые права/атрибуцию либо исключить проблемные пакеты и образцы; бесплатность приложения сама по себе вопрос не решает |
| Развлекательные клипы | В ресурсах есть сторонние ролики, включая film-drink/one-beer и другие; подтверждение прав не установлено | Инвентаризация происхождения и прав; заменить непроверенные файлы собственными перед релизом |
| SDK privacy | Bundled ML Kit, системный Android ASR и остальные библиотеки требуют проверки фактического поведения | Сверить network capture/SDK документацию с App Privacy и Data safety; не выбирать «данные не собираются» только из факта локального MT |
| Apple privacy manifests | В просмотренном дереве нет явного `PrivacyInfo.xcprivacy` | Аудит required-reason APIs и SDK signatures/manifests в финальном archive; определить обязательные declarations |
| Поддерживаемые устройства | Реальные испытания сосредоточены на iPhone17Pro, M3Pro и Pixel9Pro | Проверить минимальные ОС, малую RAM, отказ разрешений, отсутствие моделей/места, offline first-use после подготовки |
| Скриншоты | Часть Apple-экранов взята из прежних тестов | Переснять финальную сборку, правильную локаль и чистые данные; сохранить новый manifest |

Исходный код приложения в рамках комплекта не изменялся. Наличие блокера не означает, что магазин уже отказал: отправки на ревью не было.

## App Store

1. Создать/проверить app record, bundle ID и платформу; подтвердить выбранную подпись, минимальные ОС и поддерживаемые устройства.
2. Вставить локализованные поля из `copy/ios`; для Mac — `copy/macos` после отдельной технической готовности.
3. Добавить icon из asset catalog, скриншоты нужных семейств, support/privacy URL, contact/review notes, age rating и privacy disclosure.
4. Загрузить archive, устранить замечания validation, проверить TestFlight на чистой установке и обновлении с сохранёнными моделями.
5. Для preview снять реальную работу интерфейса: 15–30 с, не более500MB; подготовленный учебный слайд-ролик не выдавать за принятую Apple экранную демонстрацию. [Apple preview specs](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications).

Скриншоты: подготовленный холст iPhone1320×2868; Mac2880×1800. Проверить нужные display families в текущей форме. [Apple screenshot specs](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). Для подписи, приватности и полноты приложения использовать [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Google Play

1. Release AAB, Play App Signing, монотонный versionCode, актуальный target API, проверка всех ABI/native libraries на требования page size и установку.
2. RU/EN карточки: имя≤30, короткое описание≤80, полное≤4000. [Store setup](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en).
3. Icon512×512, feature graphic1024×500, минимум2 скриншота; комплект использует1080×1920. Для рекомендательных форматов предусмотрены4. [Preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).
4. Контакты, privacy URL, ads declaration, audience/rating, app access, Data safety и необходимые permission/foreground-service declarations. Ответы по модели «содержимое на устройстве» сверить с SDK и download-host behavior. [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
5. Проверить применимость тестового трека/production-access требований в конкретном аккаунте. В этом сеансе консоль аккаунта не проверялась.
6. Preview video при необходимости размещается на YouTube (public/unlisted, без рекламы, доступно встраивание). Файл в комплекте не загружен; публикация видео требует отдельного действия издателя.

## Финальная приёмка

Чистая установка; скачивание/пауза/возобновление/ошибка checksum; работа после отключения сети; три режима; тихая и длинная запись; отсутствие TTS; отмена и следующий перевод; история и удаление; низкое место/RAM; камера denied/retry; фон/foreground transfer; VoiceOver/TalkBack/крупный шрифт/Reduce Motion; отсутствие приватных данных в медиа. Замерить фактический набор доступных языков после отбора лицензий. Зафиксировать версии, SHA, экранные записи и результаты. Только затем отправлять материалы магазинам.
