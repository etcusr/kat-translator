# Оптимизации и ссылки на испытания

Состояние на 12.10.2026. Приведены существующие измерения, без повторного запуска в рамках подготовки материалов. Проценты относятся к описанному corpus/устройству; их нельзя помещать в магазин как универсальную гарантию.

| Изменение | Где применяется | Доказательство и результат | Ограничение |
|---|---|---|---|
| Index MTP2: основная модель проверяет до двух предложенных токенов | iPhone | [Контролируемый опыт](../../../benchmarks/iphone-index-mtp-2026-10-12/REPORT.md), [внедрение](../../../benchmarks/ios-mtp-release-2026-10-12/README.md): −17,2% по сумме 6 текстов; отмена/лимиты/reuse; прежний GGUF | Без ASR/TTS/загрузки; не доказательство для всех языков |
| Index MLX + MTP2 | Mac | [A/B](../../../benchmarks/mac-index-mlx-mtp-2026-10-12/REPORT.md), [выпуск](../../../benchmarks/mac-mlx-release-2026-10-12/README.md): сумма медиан 21,623→12,892 с, −40,4% к GGUF; −30,3% к MLX без MTP | 48 основных измерений; движок и квантование меняются; MLX ошибся в nucleobases; MTP не исправляет качество |
| Mali-G715 kernels, MMVQ policy | Android Index | [Профиль](../../../android/benchmarks/2026-10-12-pixel9pro-index-profile/README.md): warm ~8,50→7,27–7,29 с на короткой фразе | Same GGUF, не все GPU; timestamp-профиль сериализует работу и не равен обычной задержке |
| Android MTP / длинный вход | Android Index | [Mali research](../../../android/benchmarks/2026-10-12-pixel9pro-mali-research/README.md), [parity 0.3.4](../../../android/benchmarks/2026-10-12-parity-034/README.md) | Проверять включение в конкретном native profile; не подставлять iPhone −17,2% |
| AUTO allocation вместо принудительного MMAP | Android Index | [0.3.4](../../../android/benchmarks/2026-10-12-parity-034/README.md): 12,52/9,73→6,47/5,96 с подготовки при прежних весах | По 2 диагностических запуска, не cold-cache benchmark |
| Удержание OPUS/ASR, свежий stream на запись | Android | [0.3.3](../../../android/benchmarks/2026-10-12-loading-audio/README.md), [0.3.6](../../../android/benchmarks/2026-10-12-asr-routing/README.md): reuse, отмена; EN→RU→EN полный импорт+ASR+OPUS 4,015/2,647/3,787 с | Время без TTS, два синтетических fixture, загрузка при смене ASR включена |
| GigaAM, разбиение длинной записи ≤30 с, отмена | Android RU | [Полнота ASR](../../../android/benchmarks/2026-10-12-asr-completeness/README.md): проблемный 24,56-секундный ввод распознан полностью; продуктовый путь 4,227 с без TTS | Частный исходный WAV не распространять; полная запись ≠ отсутствие ошибок слов |
| PP-OCRv5 mobile detector | Android RU | [Hybrid OCR](../../../android/benchmarks/2026-10-12-hybrid-ocr/README.md): пять синтетических случаев ~2481–3747→412–601 мс, ожидаемый текст совпал | ~6× в этих fixture, не эквивалентность качества реальных фото |
| Кэш проверенных квитанций | Apple; аналог на Android | [Реализация и тесты](../../../IMPLEMENTATION-startup-verification-cache.md): iPhone первый запуск 25,88→повторный 3,08 с; Android [0.3.4](../../../android/benchmarks/2026-10-12-parity-034/README.md) 12 receipts за 145 мс | Первый запуск мигрирует квитанции; метаданные не защищают от всех видов повреждения |
| Preflight и резерв ответа | Index; отдельный лимит OPUS | [Разбиение](../../../benchmarks/translation-preflight/README.md), [ответ](../../../benchmarks/translation-output-limit/README.md), [OPUS](../../../IMPLEMENTATION-opus-big.md) | Цель — полнота и предсказуемость, не доказанный процент ускорения |
| Metal FP16 OPUS helper, одна direction в RAM | Современный Mac54 | [Релиз](../../../benchmarks/mac-opus-gpu-release-2026-10-12/README.md): 6 направлений, cancel/reuse, Index regression, упаковка | Нет нового целого app A/B; Mac15–26 не обновлён |
| Громкость оригинала отдельно от ASR | Apple/Android | [Android 0.3.4](../../../android/benchmarks/2026-10-12-parity-034/README.md): active RMS, до32× для записи Android, limiter; чанки2048 | Улучшение воспроизведения, не качества ASR; TTS имеет иной gain |
| Эксперимент до остановки записи | Whisper+Index | [iPhone опыт](../../../benchmarks/recording-preview/README.md): после Stop 3,788→0,133 с на коротком fixture | Старый опыт, не полная acoustic latency; выключено по умолчанию, нагрузка возрастает |

## Отклонённые и не перенесённые решения

- iPhone OPUS Core ML GPU: [описание в отчёте выпуска](../../../benchmarks/mac-opus-gpu-release-2026-10-12/README.md), 1,55–2,30× медленнее CPU INT8, дополнительные вставки в 2/4 случаев. В приложении остаётся CPU.
- Android OPUS Vulkan: [прототип](../../../android/benchmarks/2026-10-12-opus-vulkan/README.md), beam5 GPU медленнее CPU ~2,5–3,8×; greedy 0,341 с нельзя выдавать за beam5. Не внедрён.
- Mac MTP4 в [A/B](../../../benchmarks/mac-index-mlx-mtp-2026-10-12/REPORT.md) медленнее MTP2. Больше кандидатов не означает быстрее.
- Mali small prefill дал NaN; ubatch32 и отключение всех integer dot ухудшали скорость. [Журнал](../../../android/benchmarks/2026-10-12-pixel9pro-index-profile/README.md).

## Качество и приёмка

Проверять отрицания, числа, даты, имена, пропуски, повторы и незапрошенные объяснения. Скорость без текста результата не является достаточным основанием выбора. Сохранены [100 кинореплик](../../../benchmarks/ru-th-film100/README.md) и [72 примера регистра](../../../benchmarks/register72/README.md): ошибки и смягчение лексики исключают обещание безошибочности. Исторические выводы зависят от проверенного model snapshot.

Новый протокол: версия/устройство/ОС → точный hash модели → одинаковый corpus → отдельный warmup → чередуемые A/B с тепловым контролем → timings по этапам → сверка качества → cancel/reuse → итоговый файл и ограничения. Для публикационной рекламы использовать только проверенный продуктовый путь, не отдельный быстрый native kernel.
