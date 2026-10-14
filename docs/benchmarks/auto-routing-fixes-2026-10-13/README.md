# Исправления Auto / OPUS — 13 октября 2026

Последующий статус: iOS45 и Android code21 установлены; [проверки на телефонах](../auto-routing-devices-2026-10-13/README.md). Ниже — состояние при завершении исходной задачи.

Исходный HEAD: `fbb8d5a`, чистое дерево. Исправлены семь проблем по результатам ревью. Это проверка исправлений, не полная языковая приёмка и не сравнение скорости.

## Исправления и регрессии

| № | Ошибка и результат | Проверка |
|---|---|---|
| 1 | Apple: загруженный OPUS ограничивал список Auto четырьмя языками. Теперь Auto показывает объединённый набор доступных моделей; ручной OPUS сохраняет ограничения. | `LanguageSetupTests.testAutomaticPickerKeepsLanguagesOutsideTheCurrentlyLoadedOpusModel` |
| 2 | Apple: модель выбиралась до определения языка. Текст, ASR и preview теперь разрешают модель по фактической паре; старый контекст освобождается до загрузки нового, метрики получают его ID. Ручной режим не подменяется. | `ConversationPipelineTests`: речь, определение языка текста, обратное переключение, ручной режим, preview; реальный Mac-переход OPUS → Index → OPUS |
| 3 | Android: при Auto-переходах OPUS/Index могли остаться оба native-контекста и lease. `TranslationResources` освобождает неактивный движок до перехода, включая возврат к кешированному OPUS. | `TranslationRoutingTest.switchingModelsReleasesThePreviousRuntimeAndLeaseBeforeLoading` |
| 4 | Apple: кнопка OPUS-направлений обходила сетевое подтверждение. Теперь используется общий `DownloadButton`/`DownloadRequest`, показывающий общий объём и при ранее разрешённой сотовой сети. | Два Mac runtime-теста: разрешение, отмена, повторная загрузка и суммарный размер реальных направлений; сетевые действия заменены счётчиком |
| 5 | Android: установленные вручную OPUS-направления исключались из языкового плана из-за отсутствия хостинга. План принимает установленные ID и предпочитает их; RU↔DE больше не требует лишнюю 2B. | `PackageLanguageSetupTest.installedManualDirectionsDoNotRequireAnotherTranslationModel` |
| 6 | Android: определённый EN→EN ошибочно искал OPUS-маршрут. Оригинал теперь возвращается до разрешения модели, далее обычные история/TTS. | `TranslationRoutingTest.sameLanguagePassesThroughWithoutResolvingOrLoadingAnyModel` |
| 7 | Обе платформы: отсутствующий первый маршрут скрывал установленный групповой. Доступность теперь фильтруется до выбора первого маршрута; исправлены Auto, setup и фактический backend. Apple backend использует receipt установленного пакета. | Apple/Android `installedGroupRouteWinsOverMissingSpecificRoute`; BG→EN выбирает zls-en при отсутствии bg-en |

`AppModel.refreshVoiceFiles` обновляет resolver режима до следующего запроса, даже если переключение Auto/ручной не меняет текущую модель. Обновление голосов/ASR сохраняет resolver. Preview не отключён: он разрешает модель после своего ASR и передаёт её финальному запросу.

## Выполненные проверки

- Android: **103 unit-теста**, 0 ошибок; `lintDebug`, `assembleDebug` успешны. APK на Pixel не устанавливался.
- OfflineCore: **272 теста**, 0 ошибок, **2 штатных пропуска** opt-in тестов скачиваемых голосовых моделей.
- Mac: **4 runtime-теста и 1 UI-тест** прошли. Два теста подтверждения загрузки; проверка unload в роутере; реальный Auto-переход; реальный UI EN→FR с автоопределением исходного языка и сохранением целевого языка. Последующая проверка выявила, что строковый launch-аргумент `translationAuto=YES` не включал Auto-модель; выбор MT через Auto в этом первом UI-прогоне не доказан (native-тест выше использовал настоящий resolver). Исправленный Mac UI-тест затем прошёл в телефонной задаче по ссылке выше.
- Реальный Mac-переход использует установленный OPUS GPU и Index 9B MLX через production `RoutedTranslationBackend`/`ConversationPipeline`. Для воспроизведения ветки компактного устройства тест явно передаёт `strongDevice: false`, устанавливает доступность только имеющихся OPUS/9B и не меняет сохранённый DeviceProbe. Немецкая фраза дала “The train to Berlin departs tomorrow at 07:45.”; русская — “The train to Moscow will leave tomorrow at 07:45.”. Тексты синтетические, история отключена.
- Чувствительность регрессий: во временных копиях возвращена прежняя логика. Четыре выбранных Swift-теста и четыре Android-теста обнаруживают дефекты; рабочий код при этом не менялся. Это дополнение к успешным тестам, не замена проверки native runtime.
- iOS **0.5.15 (45)**: Release-сборка и проверка подписи `codesign --verify --deep --strict` успешны. Сохранена `dist/ios/Kat-translator-0.5.15-build45.app`.
- Проверки `scripts/validation`: **98 тестов прошли** после обновления документации. Первый прогон корректно обнаружил ещё не обновлённую строку версии iOS.

## Повторение

```sh
swift test --disable-sandbox --package-path shared/packages/OfflineCore
# В Android-каталоге, после source scripts/android/env.sh из корня:
./gradlew --offline --no-daemon testDebugUnitTest lintDebug assembleDebug
TEST_RUNNER_KAT_AUTO_ROUTING_INTEGRATION=1 xcodebuild \
  -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath.build/MacDerivedData \
  -only-testing:MacRuntimeTests/MacRuntimeTests/testAutomaticDetectedTextSwitchesRealOpusAndIndexModels \
  -only-testing:MacRuntimeTests/OpusRoutingTests \
  -only-testing:MacUITests/MacUITests/testAutomaticTextKeepsSelectedTarget test
```

Полные локальные логи сохранены в ignored `.build/auto-routing-fixes/`; Mac xcresult — в `.build/MacDerivedData/Logs/Test`. Они могут содержать локальные пути и сведения подписи, поэтому в Git входит только этот отчёт. Первоначальный Swift-запуск в песочнице завис до результатов; повтор вне неё выполнен. В новом preview-тесте исправлена фикстура: нужны законченная фраза с точкой и полноценный аудиоблок.

## Статус установки и ограничения

iPhone-проверка **ещё не выполнена**: выполняется резервное копирование устройства; на первом опросе CoreDevice показывал disconnected. сначала выполнены Mac-тесты. Установку build45 выполнить поверх приложения после окончания копирования, затем UI/перевод; не удалять контейнер, модели или историю. Нельзя считать успешную сборку проверкой на телефоне.

Mac тестировался из DerivedData; `/Applications/Kat translator.app` и Mac DMG/ZIP не заменялись. Android-версия 0.4.5/code20 и Mac 0.6.7/build60 пока остаются номерами предыдущих выпусков: исходники содержат исправления, прежние опубликованные локально артефакты — нет. Новые Mac/Android выпуски в этой задаче не упаковывались. Index 2B и отдельные OPUS-направления на Mac не прогонялись с весами: подходящих установленных пакетов нет; маршрутизация покрыта тестами, Apple-код собран для Mac и iOS. Нет новой проверки Android native-переключения на Pixel, физических сотовых загрузок и всех 54 OPUS-направлений.
