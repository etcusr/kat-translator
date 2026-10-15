# App Store: тексты RU / EN / ES / TR

Актуальный комплект для четырёх языков интерфейса iOS и Mac. Тексты подготовлены локально, без загрузки в App Store Connect. Техническая история смены ID убрана из What's New. Описания объясняют локальную обработку, первоначальную загрузку моделей и различия языковой поддержки; не обещают наличие всех моделей для скачивания или отсутствие любых сетевых запросов.

| Интерфейс | Локализация App Store Connect | iOS | Mac |
|---|---|---|---|
| Русский | Russian (`ru`) | [Тексты](ios/ru/description.txt) | [Тексты](macos/ru/description.txt) |
| English | English (U.S.) (`en-US`) | [Copy](ios/en/description.txt) | [Copy](macos/en/description.txt) |
| Español | Spanish (Spain) (`es-ES`) | [Textos](ios/es/description.txt) | [Textos](macos/es/description.txt) |
| Türkçe | Turkish (`tr`) | [Metinler](ios/tr/description.txt) | [Metinler](macos/tr/description.txt) |

Каталоги `ios/<язык>/` и `macos/<язык>/` содержат по девять файлов. Их содержимое можно копировать целиком, без имени файла:

| Файл | Поле | Проверяемый предел |
|---|---|---|
| `name.txt` | Name | 30 символов |
| `subtitle.txt` | Subtitle | 30 символов |
| `promotional_text.txt` | Promotional Text | 170 символов |
| `description.txt` | Description | 4 000 символов |
| `keywords.txt` | Keywords | 100 байт UTF-8 |
| `support_url.txt` | Support URL | 255 символов |
| `marketing_url.txt` | Marketing URL (необязательно) | 255 символов |
| `privacy_policy_url.txt` | Privacy Policy URL, раздел App Privacy | 255 символов |
| `whats-new.txt` | What's New (для обновлений) | 4 000 символов |

В [справочнике Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) для keywords указан лимит 100 байт; применён этот более строгий предел, включая кириллицу и турецкие буквы. Считаются также UTF-16 units, чтобы символ вне BMP не скрыл превышение остальных полей.

Name, Subtitle и Privacy Policy URL относятся к общей карточке iOS/Mac, поэтому их копии по платформам одинаковы. Описания и промотекст отличаются: iPhone использует камеру/фототеку, Mac — файлы изображений, буфер обмена и область экрана. Для Mac указаны Apple Silicon и macOS 27+. [Общие поля Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).

What's New не требуется для первой версии; файлы с описанием первого выпуска подготовлены на случай необходимости, но переносить их в другие поля не нужно. [Обязательные поля](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/).

## Поля App Review и оставшиеся действия

- В Notes использовать [iOS review notes](ios/review_notes.txt) или [Mac review notes](macos/review_notes.txt). Это одно поле на платформу, поэтому инструкция для ревьюера подготовлена на английском. Старые ссылки `ios/en/review_notes.txt` и `macos/ru/review_notes.txt` содержат идентичные актуальные копии.
- Sign-in required выключить: входа в приложение нет. Контакты ответственного за App Review заполнить непосредственно в кабинете.
- Copyright заполнить после подтверждения обозначения правообладателя. Старый `macos/ru/copyright.txt` не входит в проверенные девять полей и не копируется в комплект загрузки; юридическая проверка остаётся отдельной задачей.
- В ES/TR используется действующая общая страница политики на RU/EN. Наличие ES/TR текста карточки не означает перевод самой политики.
- Проверка носителями языка, App Store Preview и сохранение полей в кабинете ещё не выполнены. Горячие клавиши/захват экрана Mac описаны по реализации; приёмка окончательной sandbox/TestFlight-сборки остаётся в общем плане публикации.

Для заполнения карточки использовать один файл `dist/store/apple/APP-STORE-TEXTS.txt`: все поля сгруппированы по разделам App Store Connect и языкам, с длиной и пределом. Его и папку скриншотов собирает `python3 scripts/publication/build-apple-store-package.py`. Прежние покадровые копии — в `dist/store/_sources/localized-2026-10-14/`. Это ignored-каталог; оригиналы выше находятся в Git. Скриншоты проверяются отдельно и не создаются из этих описаний.

## Проверка

Из корня проекта:

```sh
python3 scripts/validation/check_store_metadata.py --report docs/publication/2026-10-14/metadata-validation.json
```

[Результат и SHA-256 каждого поля](metadata-validation.json): 8 локализаций, 72 поля, две инструкции для App Review. Проверяются полнота, соответствие языкам интерфейса, одинаковые общие поля, длины, keywords и синтаксис HTTPS-ссылок. Доступность URL и факт сохранения в кабинете этой проверкой не устанавливаются.

## Готовые скриншоты

[Съёмка iPhone](../localized-screenshots-2026-10-14.md) и [съёмка Mac](../localized-macos-screenshots-2026-10-14.md): по четыре экрана на RU/EN/ES/TR, всего 32 PNG. Для загрузки — `dist/store/apple/screenshots/<iPhone|Mac>/<язык>/01…04-*.png`; исходники и галерея — `dist/store/_sources/localized-2026-10-14/`. Это материалы для **App Previews and Screenshots**; Header/Search Results подготовлены отдельно. Проверка App Store Connect Preview ещё требуется.
