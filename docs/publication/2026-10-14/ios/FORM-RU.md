# Карточка iOS: русская локализация

Подготовленные значения; сохранение этих полей в App Store Connect не подтверждено. Все четыре локализации iOS и Mac — в [общем комплекте](../LOCALIZATIONS.md).

| Поле | Значение / источник |
|---|---|
| Promotional Text | [ru/promotional_text.txt](ru/promotional_text.txt) |
| Description | [ru/description.txt](ru/description.txt) |
| Keywords | [ru/keywords.txt](ru/keywords.txt), 90 байт UTF-8 |
| Support URL | https://etcusr.github.io/kat-translator/ — контакт поддержки; HTTP 200 проверен 14.10.2026 |
| Marketing URL | [ru/marketing_url.txt](ru/marketing_url.txt); необязательно |
| Version | 1.0; актуальный номер подготовленной сборки и результат проверки — в [текущем состоянии](../../../CURRENT_STATE.md) |
| Copyright | Год и действительное имя/обозначение правообладателя. Значение требует подтверждения |
| Routing App Coverage File | Не применяется |
| App Clip / iMessage App / Game Center | Не применяется |
| Build | После загрузки и обработки сборки |
| Sign-in required | Выключено: аккаунт и вход в приложение не нужны |
| Contact Information | Контакт ответственного за ответы App Review: имя, фамилия, телефон с кодом страны; email katlabs.dev@gmail.com. Личные поля заполняются непосредственно в кабинете, не в репозитории |
| Notes | [review_notes.txt](review_notes.txt) |
| Attachment | Пока не требуется |
| Version Release | Рекомендуется Manually release this version; настройка в кабинете не изменялась |

[Описание полей Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information). Контакты App Review не отображаются покупателям. Политика конфиденциальности указывается отдельно в App Privacy: https://etcusr.github.io/kat-translator/privacy/ (HTTP 200 проверен 14.10.2026).

В разделе App Previews and Screenshots нужны реальные снимки iPhone. Header/Search Results — отдельные рекламные материалы; текущие снимки интерфейса не заменяют автоматически эти широкие изображения. Кнопка Save сохраняет черновик; Add for Review относится к отдельному этапу отправки.

Предыдущие русские снимки build47 сохранены в `dist/store/ios-1.0-build47-ru/1206x2622/`; это исторический комплект. Актуальные тексты RU/EN/ES/TR подготовлены в `dist/store/localized-2026-10-14/ios/<язык>/metadata/`. Скриншоты и текст карточки проверяются отдельно; материалы build47 не означают проверку новой сборки.
