#!/usr/bin/env python3
"""Keep the offline review gallery in sync with the app playlist and cat drawing."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
GALLERY = ROOT / 'docs/branding/loading-animations/gallery'
ASSETS = ROOT / 'assets/bundled/LoadingAnimations'
RENDERER = ROOT / 'scripts/validation/render-loading-gallery.swift'
CAT_SOURCES = [ROOT / name for name in (
    'shared/apple/Shared/CatProgressDrawing.swift',
    'shared/packages/OfflineCore/Sources/OfflineCore/CatProgressMotion.swift',
    'shared/packages/OfflineCore/Sources/OfflineCore/CatLoadingPlay.swift',
    'shared/apple/Models/CatDownloadProgressView.swift',
)] + [RENDERER]
# Stable identities preserve approved previews across repository relocation.
CAT_SOURCE_IDENTITIES = ['Shared/CatProgressDrawing.swift', 'Packages/OfflineCore/Sources/OfflineCore/CatProgressMotion.swift', 'Packages/OfflineCore/Sources/OfflineCore/CatLoadingPlay.swift', 'App/Models/CatDownloadProgressView.swift', 'scripts/validation/render-loading-gallery.swift']
TITLES = dict(zip(
    ['wizard', 'monkey-work', 'cat-break', 'swing', 'one-beer', 'cat-dance', 'cat-magic', 'cat-stalk', 'cat-paw', 'porpoise', 'cat-vibe', 'film-drink', 'pigeon', 'cat-stretch', 'work-sleep'],
    ['Кот-волшебник', 'За работой', 'Кот на перерыве', 'Качели', 'Перерыв на пиво', 'Танцующий кот', 'Кот и магия', 'Кот крадётся', 'Кошачья лапка', 'Дельфин', 'Кот ловит вайб', 'Кино и напиток', 'Голубь', 'Кот потягивается', 'Работа и сон']))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()

def managed_path(root, name):
    p = Path(name)
    if p.is_absolute() or '..' in p.parts or not p.parts or p.as_posix() != name:
        raise ValueError(f'Invalid managed gallery path: {name}')
    target = root / p
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Gallery path escapes through a symlink: {name}')
    return target

def publish(root, files, check=False):
    """Remove only previously generated files; never sweep user notes or other directories."""
    inventory = root / '_generated.json'
    previous = json.loads(inventory.read_text()) if inventory.exists() else {}
    for name in set(previous) | set(files):
        managed_path(root, name)
    expected = {name: digest(data) for name, data in files.items()}
    correct = previous == expected and all((root / name).is_file() and digest((root / name).read_bytes()) == sha for name, sha in expected.items())
    if check:
        return correct
    for name, data in files.items():
        target = managed_path(root, name)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    for name in set(previous) - set(files):
        target = managed_path(root, name)
        if target.is_file():
            target.unlink()
    inventory.write_bytes(encoded(expected))
    return True

def render_cats():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise RuntimeError('ffmpeg is required to export cat previews')
    with tempfile.TemporaryDirectory(prefix='kat-gallery-') as folder:
        temp = Path(folder)
        source = CAT_SOURCES[3].read_text()
        start = source.index('private struct CatKeepsake: Shape')
        end = source.index('/// Draw the brand color', start)
        (temp / 'Keepsake.swift').write_text('import SwiftUI\n' + source[start:end].replace('private struct CatKeepsake', 'struct CatKeepsake'))
        subprocess.run(['swiftc', '-D', 'CAT_WIDGET', '-module-cache-path', str(temp / 'modules'),
                        *map(str, CAT_SOURCES[:3]), str(temp / 'Keepsake.swift'), str(RENDERER), '-o', str(temp / 'render')], check=True)
        subprocess.run([str(temp / 'render'), str(temp / 'frames')], check=True)
        catalog = json.loads((temp / 'frames/catalog.json').read_text())
        files = {}
        for row in catalog:
            name = row['id']
            video = temp / (name + '.mp4')
            def ff(*args):
                subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', *map(str, args)], check=True)
            ff('-framerate', '30', '-i', temp / 'frames' / name / '%04d.png', '-c:v', 'libx264', '-preset', 'fast', '-crf', '20', '-pix_fmt', 'yuv420p', '-threads', '2', '-an', '-movflags', '+faststart', video)
            gif = temp / (name + '.gif')
            ff('-i', video, '-filter_complex', '[0:v]fps=15,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64:reserve_transparent=0[p];[b][p]paletteuse=dither=bayer:bayer_scale=3', '-loop', '0', gif)
            poster = temp / (name + '.jpg')
            ff('-i', video, '-frames:v', '1', '-q:v', '2', poster)
            row.update({'video': f'cat/{name}.mp4', 'gif': f'cat/{name}.gif', 'poster': f'cat/{name}.jpg'})
            for key, path in [('video', video), ('gif', gif), ('poster', poster)]:
                files[row[key]] = path.read_bytes()
        return catalog, files

def page(cats, clips):
    def cards(rows, group):
        output = []
        for i, row in enumerate(rows, 1):
            title = f'{group} {i:02d} · {row["title"]}'
            e = html.escape
            gif = f'<a href="{e(row["gif"])}" download>GIF</a>' if row.get('gif') else ''
            output.append(f'<article id="{group}-{e(row["id"])}"><video src="{e(row["video"])}" poster="{e(row["poster"])}" data-title="{e(title)}" aria-label="{e(title)}" controls muted playsinline preload="none"></video><h3>{e(title)}</h3><div class="meta">{row["duration"]:.1f} сек · без звука</div><div class="downloads"><a href="{e(row["video"])}" download>MP4</a>{gif}</div></article>')
        return ''.join(output)
    return f'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kat · галерея анимаций</title><link rel="stylesheet" href="style.css"><script src="player.js" defer></script></head>
<body><h1>Kat · анимации загрузки</h1><p>Актуальные анимации приложения: {len(cats)} движений кота и {len(clips)} роликов.<br>Для оценки называйте набор и номер: например, «кот 07» или «ролик 06».</p>
<div class="toolbar"><button id="play-all" aria-pressed="false">Воспроизвести всё</button><span id="play-status" role="status" aria-live="polite">{len(cats) + len(clips)} анимации · по очереди</span></div>
<nav><a href="#cats">Нарисованный кот</a><a href="#clips">Ролики при переводе</a></nav>
<h2 id="cats">Нарисованный кот</h2><p>Рисунок и движения из приложения, увеличенные для просмотра.</p><div class="grid">{cards(cats, 'Кот')}</div>
<h2 id="clips">Ролики при переводе</h2><p>Те же MP4, которые используются во время распознавания и перевода.</p><div class="grid">{cards(clips, 'Ролик')}</div>
<footer>Галерея работает локально. Можно отправить всю папку и открыть index.html после распаковки.</footer></body></html>
'''.encode()

def build(check=False, force=False):
    fingerprint = digest(b''.join(name.encode() + b'\0' + p.read_bytes() for name, p in zip(CAT_SOURCE_IDENTITIES, CAT_SOURCES)))
    state_file = GALLERY / 'state.json'
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    valid = state.get('cat_source_sha256') == fingerprint and bool(state.get('cat_files'))
    if valid:
        valid = all(managed_path(GALLERY, name).is_file() and digest((GALLERY / name).read_bytes()) == sha for name, sha in state['cat_files'].items())
    if not valid or force:
        if check:
            # Rendered previews are excluded from Git (docs/REPOSITORY_PRIVACY.md). A clean
            # checkout has none of them; only a partially present or stale set is an error.
            if state.get('cat_files') and not any((GALLERY / name).exists() for name in state['cat_files']):
                print('Cat previews absent in this checkout (excluded from Git); gallery check skipped.', file=sys.stderr)
                return
            raise RuntimeError('Cat previews are missing or stale. Run python3 scripts/update-animation-gallery.py')
        cats, files = render_cats()
    else:
        cats = state['cats']
        files = {name: (GALLERY / name).read_bytes() for name in state['cat_files']}
    cat_hashes = {name: digest(data) for name, data in files.items()}
    clips = []
    manifest = json.loads((ASSETS / 'loading-animations.json').read_text())
    seen = set()
    for item in manifest:
        identifier, resource = item['id'], item['resource']
        if identifier in seen or not re.fullmatch(r'[A-Za-z0-9_-]+', identifier) or not re.fullmatch(r'[A-Za-z0-9_-]+', resource):
            raise ValueError(f'Invalid or duplicate clip: {identifier}')
        seen.add(identifier)
        row = {'id': identifier, 'title': item.get('title') or TITLES.get(identifier, identifier.replace('-', ' ').capitalize()), 'duration': item['duration'], 'video': f'clips/{identifier}.mp4', 'poster': f'clips/{identifier}.jpg'}
        files[row['video']] = (ASSETS / (resource + '.mp4')).read_bytes()
        files[row['poster']] = (ASSETS / (resource + '.jpg')).read_bytes()
        row['sha256'] = digest(files[row['video']])
        clips.append(row)
    files['catalog.json'] = encoded({'cats': cats, 'clips': clips})
    files['state.json'] = encoded({'cat_source_sha256': fingerprint, 'cats': cats, 'cat_files': cat_hashes})
    files['index.html'] = page(cats, clips)
    for name in ['player.js', 'style.css']:
        files[name] = (ROOT / 'scripts/animation-gallery' / name).read_bytes()
    return files

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Read-only freshness check; no compiler/ffmpeg required when up to date')
    parser.add_argument('--render-cats', action='store_true', help='Force a fresh native cat export')
    parser.add_argument('--zip', action='store_true', help='Also export a current shareable ZIP into dist/share')
    args = parser.parse_args()
    if args.check and (args.zip or args.render_cats):
        parser.error('--check cannot be combined with write options')
    files = build(check=args.check, force=args.render_cats)
    if files is None:
        return
    if not publish(GALLERY, files, check=args.check):
        raise RuntimeError('Gallery is stale. Run python3 scripts/update-animation-gallery.py')
    if args.zip:
        archive = ROOT / 'dist/share/Kat-loading-animations-current.zip'
        archive.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            for name, data in files.items():
                z.writestr('Kat-loading-animations/' + name, data)
        print(archive)
    print(('Verified' if args.check else 'Updated') + f' gallery: {GALLERY / "index.html"}')

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, FileNotFoundError) as error:
        sys.exit(str(error))
