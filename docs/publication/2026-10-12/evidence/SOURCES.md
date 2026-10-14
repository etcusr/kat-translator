# Источники и метод

12.10.2026. Проверены текущие Info.plist/Gradle, UI/theme/privacy/recognition routing и manifests. Числа производительности взяты из ссылок в OPTIMIZATIONS, тесты заново не выполнялись. Android установленная версия дополнительно подтверждена dumpsys:0.3.6/versionCode11,minSdk31,targetSdk36. В интерфейсе при съёмке выбран OPUS; историческое описание последнего теста с Index не выдаётся за текущий пользовательский выбор.

Официальные требования, открытые при подготовке:
- Apple screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Apple app preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- Apple platform version metadata: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Apple review guidelines: https://developer.apple.com/app-store/review/guidelines/
- Google preview assets: https://support.google.com/googleplay/android-developer/answer/9866151?hl=en
- Google store setup: https://support.google.com/googleplay/android-developer/answer/9859152?hl=en
- Google Data safety: https://support.google.com/googleplay/android-developer/answer/10787469?hl=en

Реестры моделей и языков — извлечение локально закреплённых данных, не новый юридический/качественный аудит каждой внешней карточки. UI-снимки Apple не считаются свежей проверкой установленного build36/54. Отсутствие явного PrivacyInfo в просмотренных путях — повод проверить archive, не утверждение об отсутствии manifest внутри каждого SDK.
