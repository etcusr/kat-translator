#!/usr/bin/env python3
"""Replace the baked captions in the normalized 384x288 cat clip (macOS)."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def localize(source: Path, destination: Path):
    metadata = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height', '-of', 'json', str(source)
    ]))['streams'][0]
    if (metadata['width'], metadata['height']) != (384, 288):
        raise ValueError('Normalize the video to 384x288 before localizing its captions')
    with tempfile.TemporaryDirectory(prefix='kat-cat-caption-') as folder:
        temp = Path(folder)
        overlay = temp / 'caption.png'
        subprocess.run([
            'swift', '-module-cache-path', str(temp / 'modules'),
            str(Path(__file__).with_name('render-cat-break-caption.swift')), str(overlay)
        ], check=True)
        output = temp / 'english.mp4'
        subprocess.run([
            'ffmpeg', '-v', 'error', '-y', '-i', str(source), '-i', str(overlay),
            '-filter_complex', '[0:v][1:v]overlay=0:0:format=auto,format=yuv420p[v]',
            '-map', '[v]', '-an', '-sn', '-dn', '-map_metadata', '-1',
            '-c:v', 'libx264', '-preset', 'slow', '-crf', '24',
            '-movflags', '+faststart', str(output)
        ], check=True)
        destination.write_bytes(output.read_bytes())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    localize(args.source, args.destination)
