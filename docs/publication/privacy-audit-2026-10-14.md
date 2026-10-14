# Конфиденциальность: код, SDK и публичная страница

Актуальное продолжение: [аудит App Privacy/SDK и пакеты iOS49/Mac68](apple-privacy-sdk-2026-10-14.md). Также подготовлена [новая классификация сторонних загрузок](model-download-privacy-2026-10-14.md); обновлённая политика опубликована и проверена; подтверждение приведено в новом отчёте. Результаты ниже относятся к прежнему составу и прежней опубликованной редакции.

Сверено 14 октября 2026. Контакт **katlabs.dev@gmail.com** предоставлен пользователем специально для публичной политики. публикацию GitHub Pages по адресу `https://etcusr.github.io/kat-translator/privacy/`.

Канонический RU/EN текст — [site/privacy/index.html](../../site/privacy/index.html). Главная/support — [site/index.html](../../site/index.html). Workflow публикует **только site/**, не рабочую папку или весь docs. На странице нет JavaScript, сторонних шрифтов, аналитики и форм; технические обращения к хостингу GitHub Pages описаны отдельно.

## Установлено по реализации

| Область | Подтверждение в коде | Отражение в политике |
|---|---|---|
| Модели/перевод | Apple native backends; `shared/native/OpusGPU/opus_gpu.py` задаёт offline/local_files_only; IndexMLX включает HF_HUB_OFFLINE; Android native Index/CT2/sherpa | Перевод локальными моделями, без обещания отсутствия любых запросов всех SDK |
| Загрузки | `ModelDownloader.swift`: URLSession download; Android `ResumableDownload.kt`: HTTPS GET/Range/ETag и redirects; remoteURL из каталогов | Hugging Face/GitHub/CDN получают сведения соединения и запрошенного файла |
| Android OCR | `app/build.gradle.kts`: пять bundled `com.google.mlkit:text-recognition*:16.0.1`; runtime audit содержит datatransport | Отдельно раскрыта обработка технических метрик Google ML Kit |
| Android ASR | `SystemSpeechRecognizer.kt`: `createOnDeviceSpeechRecognizer`, проверка локальной службы | Системный on-device режим; не обещать отсутствие собственной диагностики ОС |
| История Apple | `TranslationHistory.swift`: текст, M4A/PNG, `saveOriginalRecording`; `ConversationPipeline.swift` вызывает сохранение оригинала; Settings defaults true | Исходная запись может сохраняться при включённом аудио. Старое «не сохраняется» было неверно |
| История Android | `TranslatorState.kt`: archive сохраняет originalAudio, speech и image; defaults true; `deleteHistory`, `clearHistory`, `pruneHistory` | Отдельные настройки, очистка/сроки/лимиты; выключение сохранения не стирает старое |
| Удаление | Apple remove/removeAll удаляют принадлежащие истории медиа; Android удаляет файлы записи; pruning запускается кодом приложения | Не обещать таймер удаления при закрытом приложении или удаление экспортов/backup |
| Временные файлы | `TemporarySpeechFiles`, `TextSpeechShareCache`, `HistoryExports`; Android cache/exports очищается при инициализации | Очистка истории не равна полному стиранию всех кэшей/текущего результата |
| Backup | Android manifest allowBackup=false; Apple model/transfer paths помечаются excludedFromBackup, история находится под общим root | Не обещать полный контроль над ОС/OEM-переносом и внешними резервными копиями |
| Поделиться/диагностика | Системные clipboard/share; Android diagnostics содержит технические показатели и модель устройства; Apple отчёт по действию пользователя | Получатель выбирается пользователем; проверить отчёт до отправки |
| Контакт | Gmail-адрес | Добровольная переписка с поддержкой отдельно от отсутствия автоматического сбора разработчиком |

## Сторонние сведения

Google прямо описывает локальную обработку входа/результата и отправку метрик: [ML Kit Terms & Privacy](https://developers.google.com/ml-kit/terms). [Android disclosure](https://developers.google.com/ml-kit/android-data-disclosure) перечисляет device/app metadata, per-installation identifier для bundled features, performance/configuration/sizes/events/errors. Нельзя делать вывод «нет встроенной телеметрии вообще» только потому, что у Kat нет собственного backend/аналитики. Таблица Google описывает актуальные SDK; окончательную Data safety декларацию сверить с фактически поставляемой версией.

[GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages) ведёт технические журналы, включая IP посетителя. Это описано на странице даже при отсутствии наших скриптов.

## Решение по публичным формулировкам

 описание продукта короткое: офлайн-переводчик с локальными моделями, интернет для загрузки пакетов. Без обещаний анонимности/отсутствия всех сетевых обращений. В политике: разработчик не собирает пользовательские данные через приложение; тексты/аудио/изображения/переводы автоматически разработчику не передаются. Добровольная переписка, Share и независимые сторонние технические данные раскрыты отдельно.

Исправлены тексты Privacy/History в Apple и Android, добавлена ссылка на политику. Поведение обработки, SDK и их телеметрия не менялись. Версии не повышались этой правкой; уже установленные приложения не получают текст без обновления.

## Границы проверки

Выполнены чтение реальных путей кода, каталогов и зависимости SDK, проверка RU/EN локализации, статического HTML и его ссылок. Это **не перехват сетевого трафика финальных IPA/APK**, не независимый аудит закрытых SDK и не заполнение App Privacy/Data safety в кабинетах. Проверку финальных сборок и согласование деклараций не считать завершёнными по одному опубликованному URL. Юридическое имя владельца developer-аккаунта не вымышлено и остаётся отдельным полем подготовки магазина.

## Публикация страницы — 14 октября 2026

GitHub Pages deployment завершён успешно. Главная страница https://etcusr.github.io/kat-translator/ и политика https://etcusr.github.io/kat-translator/privacy/ возвращают HTTP 200 без авторизации; опубликованные HTML побайтово совпадают с `site/index.html` и `site/privacy/index.html`. RU/EN текст и контакт проверены в браузере. Это подтверждение доступности сайта, не дополнительный сетевой аудит приложения.
