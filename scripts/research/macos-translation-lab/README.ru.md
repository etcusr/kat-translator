# Эксперимент с переводом на Mac

[English](README.md) | **Русский**

Отдельное локальное приложение **Kat Translation Lab** сравнивает Apple
Translation с движками Kat Index 2B и Index 9B MLX + MTP2. Оно не заменяет
установленное приложение, не меняет его настройки/историю и не создаёт
сборку для магазина.

Нужны этот рабочий каталог с существующими моделями и зависимостями,
Apple Silicon, Xcode и macOS 27+. Это локальная сборка разработчика,
не переносимый дистрибутив. Путь рабочего каталога записывается в
игнорируемый ресурс сборки; веса в приложение не копируются.

```sh
python3 scripts/research/macos-translation-lab/build.py
open ".build/mac-system-translation-2026-10-20/Kat Translation Lab.app"
```

Выберите движок и направление RU→EN или EN→RU, введите фразу либо
выберите пример, затем нажмите «Перевести». Контекст включайте в исходный
абзац: эксперимент переводит весь абзац, а не только последнюю фразу.
Ручной ввод и результат не сохраняются. При каждом нажатии Kat запускает
новый процесс; интерфейс отдельно показывает загрузку модели и перевод.

Apple использует сессию для установленных языков. Если модели отсутствуют,
нажмите «Подготовить языки Apple» для выбранного направления/режима
и подтвердите системную загрузку при необходимости. `highFidelity` —
**предпочтение**, допускающее переход к обычным моделям; выбор этого
пункта не доказывает использование весов Apple Intelligence. Во время
записанного эксперимента сеть физически не отключалась.

## Повторение сравнения на синтетических данных

Запускайте последовательно, чтобы движки не конкурировали за ресурсы.
Окно Apple должно оставаться открытым до сообщения о завершении.
Закройте приложение перед запуском другого экземпляра. Бенчмарк
записывает только встроенные синтетические примеры, не ручной ввод.

```sh
open -n ".build/mac-system-translation-2026-10-20/Kat Translation Lab.app" --args \
  --benchmark "$PWD/.build/mac-system-translation-2026-10-20/apple.json"
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/macos-translation-lab/kat_runner.py \
  index2b --fixtures tests/fixtures/mac-system-translation.json \
  --output .build/mac-system-translation-2026-10-20/index2b.json
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/macos-translation-lab/kat_runner.py \
  index9b --fixtures tests/fixtures/mac-system-translation.json \
  --output .build/mac-system-translation-2026-10-20/index9b.json
python3 scripts/research/macos-translation-lab/summarize.py \
  .build/mac-system-translation-2026-10-20
```

Аргумент приложения `--probe-kat OUTPUT.json` проверяет запуск обоих
движков Kat на одном встроенном примере с контекстом. Отдельный
`kat_runner.py index2b` или `index9b` принимает объект примера через
stdin и возвращает JSON через stdout.

Первый проход отделён от трёх повторных прогретых проходов. Это не
проверка холодного системного кеша/модели. Все выбросы задержек
сохраняются в итогах. Проверяется перевод, а не микрофон, OCR, TTS,
весь сетевой трафик устройства, длительный нагрев или приёмка
основного интерфейса приложения.

[Результаты и проверка качества](../../../docs/benchmarks/mac-system-translation-2026-10-20/README.md).
