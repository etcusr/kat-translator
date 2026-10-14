# Android 0.3.8 (13): Index 2B и флаги CPU — 12 октября 2026

Решение пользователя после [аудита скорости](../2026-10-12-pixel-speed-audit/README.md): встроить Index 2B. Выбранный вариант — «OPUS + 2B»:
- для новых установок по умолчанию остаётся OPUS;
- Index 2B становится рекомендуемой многоязычной моделью для остальных языков;
- Index 9B остаётся опцией «максимальное качество».

Переключение дефолта — одна константа.

## Изменения

- `assets/catalogs/models.json`: пакет `indexTranslation2B` / `index-translate-2b-q4km`. Официальный GGUF IndexTeam rev `3a0eca6ce931d88d00614d427ab3ed8ff0743902`, 1,312,164,352 байт, SHA-256 `044b313d…d2746a`, `platforms: [android]`. `SharedModelAssets.swift` перегенерирован; добавлен неиспользуемый дескриптор, поведение Apple не меняется. Пакет внесён в `docs/android/portability-contract.json`.
- `PackageCatalog.kt`: backend `index2b`, константы `INDEX2B_ID`, `MULTILINGUAL_BACKEND`, `INDEX_MODELS`. Языки — тот же список Index (150).
- `TranslatorState.kt`: 2B загружается из receipt-проверенного пакета с lease; 9B — прежним путём. `mtpActive` включает MTP только для 9B: на 2B MTP не ускорял (17,7 против 17,1 с в предыдущем отчёте). Добавлены метка рантайма и диагностика.
- UI (`ProductModels.kt`, `KatApp.kt`): порядок OPUS → Index 2B → Index 9B. Метка «Рекомендуется для других языков» у 2B, «максимальное качество» у 9B; тексты на RU и EN.
- `inference/src/main/cpp/CMakeLists.txt`: `GGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16`. Раньше arch не задавался, и NDK собирал под `armv8-a`.
  - i8mm намеренно не включён: на Index 2B CPU dotprod+fp16 дал pp128 73,4 / tg32 15,5 ток/с, с i8mm — 79,7 / 16,0 (в пределах шума), без флагов — 30,4 / 12,8.
  - Без i8mm сборка совместима с Tensor G1/G2 и Snapdragon 865/888.
  - `GGML_CPU_ALL_VARIANTS` требует `GGML_BACKEND_DL`, то есть динамических `.so` ggml. Это изменило бы статическую упаковку `kat_index`, поэтому не применялось.
- `index_jni.cpp`: до любых вызовов ggml проверяется HWCAP (ASIMDDP, ASIMDHP, FPHP). На старых ядрах A53/A73 Index выдаёт понятную ошибку вместо SIGILL. На таком устройстве не проверено.
- Версия 0.3.7/12 → 0.3.8/13. Новый instrumentation-тест `Index2BAppFlowTest`; unit-тесты каталога и плана загрузки дополнены.

## Проверки

- `scripts/android/build.sh`: проверки каталога/UI-каталога и pin llama.cpp. `testDebugUnitTest` — 98 тестов, 0 ошибок; `lintDebug` — 0 ошибок (53 предупреждения); `assembleDebug` и `assembleDebugAndroidTest` собраны. В `build.ninja` подтверждён `-march=armv8.2-a+dotprod+fp16`.
- Python validation: 91 из 92. Единственный провал — `test_apple_build_membership_preserved` (лишний `MLXRuntime.c` в Apple membership). Он воспроизводится и без изменений этой задачи.
- APK `dist/android/kat-translator-0.3.8-debug.apk`, SHA-256 `6f64074accac5ef60eab49bbee50dd78a35f5b7347a724b6711a3838b74d9460`, debug-подпись.
- Pixel 9 Pro: `adb install -r` поверх 0.3.7, данные сохранены. Index 2B импортирован по USB существующим `AppOwnedPackageFixtureTest`: приложение само сверило размер и SHA. Источник — исследовательская копия на телефоне. **Скачивание из сети внутри приложения в этой сессии не проверялось.** Отдельно проверены URL, `x-linked-size` и `x-linked-etag` = SHA каталога.
- `Index2BAppFlowTest`: реальные текстовые контролы, под `thermal_control.py`, термически валиден. Статья — та же, что в аудите (797 символов, локальная, в Git не входит):

| Шаг | Перевод | Загрузка модели | Первый токен |
|---|---|---|---|
| RU→EN, первый | 18,5 с | 2,2 с | 4,1 с |
| RU→EN, повтор | 17,5 с | — | 3,3 с |
| EN→RU (обратный перевод результата) | 22,7 с | — | 2,6 с |
| Отмена во время перевода | — | — | — |
| RU→EN после отмены | 17,1 с | — | 3,2 с |
| RU→EN после выгрузки и повторной загрузки | 15,7 с | 1,3 с | 3,1 с |

  Отмена прошла: оверлей закрылся, следующий запрос выполнился. Числа 12 и 309 сохранены во всех ответах, ответ один сегмент. Для сравнения: 9B в приложении на этой статье около 46 с с MTP.
- Регрессия 9B: `ProcessingCancellationTest` (9B, отмена и повторный перевод) — OK под thermal guard.
- После тестов `UiTestEnvironment` вернул пользовательские настройки, включая выбранную модель.

## Ограничения

Качество 2B проверено только на RU↔EN. Многоязычная приёмка против 9B не выполнена. Модель на телефоне не скачивалась через приложение. Устройство без dotprod/FP16 не проверялось.
