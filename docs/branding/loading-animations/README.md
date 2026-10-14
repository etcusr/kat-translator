# Processing animations

## Английская подпись cat-break — 14 октября 2026

Ролик `cat-break` и его постер теперь содержат **CAT BREAK** вместо двух русских подписей. Он общий для всех языков iOS/macOS/Android; фильтра по языку нет. H.264 384×288, 24 fps, 103 кадра / 4,292 секунды, без звука. Чёрные полосы закрывают прежние подписи, центральная область сохраняет движение кота.

`prepare-loading-animations.py` автоматически применяет `localize-cat-break.py` после нормализации этого ролика. Локализатор использует ffmpeg и macOS AppKit (`render-cat-break-caption.swift`) для воспроизводимого текстового слоя; исходник должен иметь размер 384×288. Постер снимается из нового видео. Исходные SHA в каталоге относятся к первоначальным роликам; преобразование отмечено полями `caption`/`captionLanguage`. Изменение надписи не меняет происхождение и права на исходный клип.

Актуальные галерея и ZIP обновлены; отдельное GIF-превью: `dist/share/loading-cat-break-en.gif`. Установленные/ранее загруженные приложения получат замену после обновления сборки.

## Постоянная галерея — 11 октября 2026

Текущий набор: 10 движений кота и 14 роликов. 14 октября `one-beer` удалён из ресурсов всех платформ и генератора; старые подписанные пакеты остаются историческими артефактами. Добавлен трюк с лужицей и прыжком через неё; «Кучка» теперь заканчивается закапыванием задними лапами. Оба сценария входят в последовательное воспроизведение. Отскок начинается заранее и включает толчок, подбирание лап и мягкое приземление. Перед лужицей видны три коротких сокращения корпуса; закапывание сохранено.

[Открыть галерею](gallery/index.html). Здесь находятся **только актуальные** движения нарисованного кота и ролики приложения. Кнопка **«Воспроизвести всё»** запускает их по очереди, показывает текущий номер и останавливает просмотр при повторном нажатии. Отдельные карточки тоже можно воспроизводить и скачивать. HTML работает после распаковки всей папки без сервера и интернета.

**Правило дальнейшей работы:** добавление, изменение или удаление анимации всегда сопровождается обновлением этой галереи. Исторические экспорты в `dist/share/*-2026-10-11` остаются снимками; поддерживаемый каталог — `gallery/`.

```bash
python3 scripts/update-animation-gallery.py          # обновить текущую галерею
python3 scripts/update-animation-gallery.py --zip    # также архив для отправки друзьям
python3 scripts/update-animation-gallery.py --check  # только проверка актуальности
```

Источник списка роликов — `assets/bundled/LoadingAnimations/loading-animations.json`; новые элементы автоматически получают карточку, удалённые исчезают из HTML и управляемых файлов. Можно указать `title` в записи манифеста для подписи нового ролика. Экспорт кота использует текущие SwiftUI-рисунок, модели движения, `CatLoadingPlay.Trick.allCases` и форму из приложения. Новые случайные трюки автоматически попадают в экспорт; если для трюка нужен особый запуск, экспорт явно остановится до обновления сценария, а не пропустит его незаметно.

Изменение исходников кота инвалидирует экспорт: следующий запуск перерисует MP4/GIF/постеры через SwiftUI и ffmpeg. При неизменном коде тяжёлый экспорт повторно не выполняется. `--check` не требует ffmpeg или компиляции. HTML/CSS/JS генерируются из `scripts/update-animation-gallery.py` и `scripts/animation-gallery/`; вручную менять файлы в `gallery/` не нужно.

Подготовка новых роликов автоматически обновляет галерею. Генераторы iOS/macOS-проектов и упаковка Mac проверяют её актуальность до записи проекта/сборки пакета. Синхронизация удаляет только файлы из собственного `_generated.json`, сохраняя любые сторонние заметки. Регрессии добавления/удаления/границ папки: `python3 scripts/validation/test_animation_gallery.py`.

Текущий архив для друзей: `dist/share/Kat-loading-animations-current.zip`. Он содержит всю папку с HTML и медиа; для просмотра достаточно распаковать и открыть `index.html`. Перекодирование роликов приложения для галереи не выполняется.


The user supplied fourteen Telegram MP4 clips. They join the existing wizard cat in a shared local playlist for **only the former CatWizardView locations** in Voice/Text processing. Model-preparation and download-progress cats remain unchanged.

- 14 clips, shuffled without replacement; no consecutive repeat across shuffle cycles or separate waits in one app process.
- Clip selection survives SwiftUI body updates. From Mac29 / iPhone18, each clip plays once, then the playlist advances at its end. Short clips no longer repeat to fill 8 seconds. Completion/cancellation dismisses the animation immediately.
- One muted AVPlayer and one current item per visible surface; no audio-session changes. Playback pauses when the app is inactive or Reduce Motion is on; a poster remains visible. Dismantling removes the observer and player item.
- Bundled H.264, 384×288, aspect-fit and black padding, frame rate capped at 24 fps, all audio removed. Original source identities are retained in the manifest; raw source files are not distributed in the repository. Only the persistent letterbox on `giphy.mp4` is cropped, not subjects or captions.
- `scripts/prepare-loading-animations.py` reproduces the assets with ffmpeg/ffprobe. `assets/bundled/LoadingAnimations/loading-animations.json` records original names, SHA-256 hashes, output sizes and durations. Total video size: 1,628,520 bytes; JPEG posters are additional.

## Central processing overlay (Mac29 / iPhone18)

Voice recognition/audio import and text translation now display one large animation in a shared overlay above the dimmed workspace. Width adapts to the available area, up to 640pt, preserving the 4:3 canvas. Status, optional real part/character progress, and a 44pt minimum Cancel button remain visible. The underlying workspace is disabled and hidden from accessibility while processing. Cancellation uses the existing pipeline cancellation path; keyboard editing ends when the overlay appears.

The overlay ends when processing completes or speech starts, so automatic speech leaves results readable. It is not used for model preparation/downloads, Image, or ongoing microphone capture. Existing small speech-preparation indicators remain available. Short clips now play only once before selecting the next clip, at the user's request.

Validation: Mac native UI test passed (25.868s), including centered Cancel, cancellation, actual text editing afterwards, restart and translated result. iPhone native UI test passed (50.381s), including overlay sizing/cancel target, cancellation/restart and return to results. Mac automatic-playback visibility test passed (1.524s). Final playlist tests passed 4/0 failures (6.940s), including real first-play advancement and native poster/video handoff. Screenshots on both devices reviewed. Evidence: `.build/processing-overlay/`. The first Mac UI attempt failed on an unreliable NSTextView accessibility enabled flag; testing actual editing replaced that assertion and passed.

## Verification

Evidence is stored under `.build/loading-clips/`. The original contact sheets and normalized poster sheet were visually inspected. `LoadingAnimationTests` checks the bundled media, shuffle fairness, real playback/end transitions, pause, dismissal cleanup, and the native Mac video/poster handoff.

Validated releases: **Mac28 / iPhone17**, installed and launched normally on 9 October 2026.

- Mac: 4 targeted runtime tests, 0 failures, 12.206s. Includes real native video rotation/poster visibility and decoder cleanup.
- iPhone: production text translation UI test, 0 failures, 43.555s; successful translation, clearing, and screenshots reviewed. This short UI check is not an exhaustive on-phone playlist playback test.
- Both bundles: all 15 clips and posters verified against normalized assets; signatures passed.
- Mac DMG: checksum verified; dependency audit found no external non-system libraries across 86 Mach-O files.
