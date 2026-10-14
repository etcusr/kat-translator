# Карточка iOS: русская локализация

Подготовленные значения; сохранение этих полей в App Store Connect не подтверждено.

| Поле | Значение / источник |
|---|---|
| Promotional Text | [ru/promotional_text.txt](ru/promotional_text.txt) |
| Description | [ru/description.txt](ru/description.txt) |
| Keywords | [ru/keywords.txt](ru/keywords.txt), 90 байт UTF-8 |
| Support URL | https://etcusr.github.io/kat-translator/ — контакт поддержки; HTTP 200 проверен 14.10.2026 |
| Marketing URL | Можно оставить пустым |
| Version | В карточке 1.0; текущая iOS-сборка 0.5.16/46. Перед загрузкой номер магазинной версии и CFBundleShortVersionString нужно согласовать; смена версии ещё не выполнена |
| Copyright | Год и действительное имя/обозначение правообладателя. Значение требует подтверждения; автоматически не переносить имя владельца developer-аккаунта |
| Routing App Coverage File | Не применяется |
| App Clip / iMessage App / Game Center | Не применяется |
| Build | После загрузки и обработки сборки |
| Sign-in required | Выключено: аккаунт и вход в приложение не нужны |
| Contact Information | Контакт ответственного за ответы App Review: имя, фамилия, телефон с кодом страны; email katlabs.dev@gmail.com. Личные поля заполняются непосредственно в кабинете, не в репозитории |
| Notes | [en/review_notes.txt](en/review_notes.txt) |
| Attachment | Пока не требуется |
| Version Release | Рекомендуется Manually release this version; настройка в кабинете не изменялась |

[Описание полей Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information). Контакты App Review не отображаются покупателям. Политика конфиденциальности указывается отдельно в App Privacy: https://etcusr.github.io/kat-translator/privacy/ (HTTP 200 проверен 14.10.2026).

В разделе App Previews and Screenshots нужны реальные снимки iPhone. Header/Search Results — отдельные рекламные материалы; текущие снимки интерфейса не заменяют автоматически эти широкие изображения. Кнопка Save сохраняет черновик; Add for Review относится к отдельному этапу отправки.

Обновление: исходники и локальный магазинный IPA теперь 1.0 (47). Новые русские снимки — `dist/store/ios-1.0-build47-ru/1206x2622/`; черновики ES/TR — соседние папки. [Проверки и открытые вопросы](../../ios-release-preflight-2026-10-14.md).
