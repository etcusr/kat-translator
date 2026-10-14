# Платформы и общие ресурсы

За основу взято последнее рабочее дерево 11.10.2026: iOS **0.5.3 (32)**,
Mac **0.5.4 (52)**, включая последние исправления идентичности строк голосов
и языков перевода области экрана. Git-ветка не сбрасывалась.

| Каталог | Назначение |
|---|---|
| `apps/ios` | iPhone entrypoint, камера, Live Activity, Xcode project, подпись, UI tests |
| `apps/macos` | Mac entrypoint, окна/захват экрана, Xcode project, Mac tests |
| `apps/android` | Gradle project, Android UI, JNI, тесты на устройстве |
| `shared/apple` | SwiftUI, AppModel и интеграции, используемые обеими Apple-платформами |
| `shared/packages` | Общие Swift packages; вложенные C targets принадлежат своим пакетам |
| `shared/native` | C/C++ runtime и платформенные C adapters |
| `assets/catalogs` | Единственный редактируемый каталог моделей и подробные manifests |
| `assets/bundled` | Общие маленькие ресурсы, локализация, превью голосов, OCR-словари |
| `model-store` | Ignored модели и голоса, один экземпляр на компьютере |
| `Dependencies` | Закреплённые vendor sources и сборочные артефакты, отдельные для ОС/ABI |
| `tests` | Общие benchmark fixtures и проверки |

`models.json` содержит исходные ID, URL, размер и SHA-256. Команда
`python3 scripts/generate-model-catalog.py` генерирует Swift adapter;
`--check` запрещает рассинхронизацию. Android подключает `assets/catalogs`
напрямую через Gradle source set, без редактируемой копии каталога.
`platforms` обозначает переносимость файла; успешность runtime отдельно
подтверждается испытанием на каждой ОС. Core ML-пакеты не включаются в Android.

Index хранится по digest в `model-store/blobs/sha256`, старое имя в `downloads`
является ссылкой. Импорт `scripts/models/blob_store.py` проверяет размер и SHA,
создаёт hardlink и атомарно заменяет исходное имя симлинком: блоки данных не
копируются. Остальные существующие загрузки сохранены в общем `downloads`.
`Dependencies/downloads` временно ссылается на это же дерево для старых утилит.

Проверка миграции: Python layout/catalog tests; 261 Swift tests, 2 прежних
пропуска; iOS и Mac Release `BUILD SUCCEEDED`. Источники/ресурсы обеих Xcode
build phases сравнены с исходным проектом; добавлен только общий `models.json`.
Bundle IDs, версии и настройки подписи сохранены. Приложения на Apple-устройствах
не переустанавливались. Снимок исходников, membership и логи находятся в
`.build/platform-layout/{before,after}`. Проверка сборки не заменяет UI-прогон.

Сборка из корня:

```bash
python3 scripts/generate-project.py
python3 scripts/generate-macos-project.py
swift test --package-path shared/packages/OfflineCore
xcodebuild -project apps/ios/OfflineTranslator.xcodeproj -scheme OfflineTranslator -configuration Release -destination 'generic/platform=iOS' -derivedDataPath.build/DerivedData build
xcodebuild -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath.build/MacDerivedData build
```
