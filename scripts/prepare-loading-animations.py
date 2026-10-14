#!/usr/bin/env python3
"""Normalize the supplied clips for silent, local loading animation playback."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "assets/bundled/LoadingAnimations"
SOURCES = [
    ("wizard", "assets/bundled/CatWizard/cat-wizard.mp4", None),
    ("monkey-work", "4_6041982296330863639.mp4", None),
    ("cat-break", "CapCut_vdzQ5Zc8nt (online-video-cutter.com).mp4", None),
    ("swing", "IMG_6652.MP4", None),
    ("cat-dance", "cat-dance-dancing-cat.mp4", None),
    ("cat-magic", "cat-magic.mp4", None),
    ("cat-stalk", "cat-stalk.mp4", None),
    ("cat-paw", "doc_2025-09-15_21-44-19.mp4", None),
    ("porpoise", "dumb-porpoise-i'm-stupid.mp4", None),
    ("cat-vibe", "giphy.gif.mp4", None),
    # Remove only the persistent black letterbox measured across the whole clip.
    ("film-drink", "giphy.mp4", "crop=476:308:2:36"),
    ("pigeon", "mp4.mp4", None),
    ("cat-stretch", "redditsave.com_morning_stretch-njmis5p0sze91.mp4", None),
    ("work-sleep", "work-and-sleep-work-sleep.mp4", None),
]


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)
    ]))


def prepare():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    clips = []
    for identifier, source_name, crop in SOURCES:
        source = ROOT / source_name
        original = probe(source)
        stream = next(s for s in original["streams"] if s["codec_type"] == "video")
        numerator, denominator = map(int, stream["avg_frame_rate"].split("/"))
        fps = min(24, numerator / max(1, denominator))
        resource = "loading-" + identifier
        video = DESTINATION / (resource + ".mp4")
        poster = DESTINATION / (resource + ".jpg")
        filters = ([crop] if crop else []) + [
            "scale=384:288:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos",
            "pad=384:288:(ow-iw)/2:(oh-ih)/2:black", "setsar=1", f"fps={fps:.6f}"
        ]
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", str(source), "-map", "0:v:0",
            "-vf", ",".join(filters), "-an", "-sn", "-dn", "-map_metadata", "-1",
            "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(video)
        ], check=True)
        if identifier == "cat-break":
            subprocess.run([
                sys.executable, str(ROOT / 'scripts/localize-cat-break.py'),
                str(video), str(video)
            ], check=True)
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", str(video), "-frames:v", "1",
            "-q:v", "2", str(poster)
        ], check=True)
        final = probe(video)
        clips.append({
            "id": identifier, "resource": resource, "duration": float(final["format"]["duration"]),
            "source": source_name, "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "bytes": video.stat().st_size, "width": 384, "height": 288
        })
        if identifier == "cat-break":
            clips[-1].update(caption="CAT BREAK", captionLanguage="en")
        assert len(final["streams"]) == 1 and final["streams"][0]["codec_type"] == "video"
        print(f"{identifier}: {video.stat().st_size:,} bytes", flush=True)
    (DESTINATION / "loading-animations.json").write_text(json.dumps(clips, indent=2) + "\n")
    print(f"Total: {sum(c['bytes'] for c in clips):,} video bytes")
    subprocess.run([sys.executable, str(ROOT / 'scripts/update-animation-gallery.py')], check=True)


if __name__ == "__main__":
    prepare()
