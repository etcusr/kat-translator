#!/usr/bin/env python3
"""Speed up the silent master and add an original, synthesized instrumental bed.

Requires NumPy and FFmpeg. Always use the 1x silent master and its original VTTs,
not a previous finished export. No recordings, samples or external music assets.
"""
import argparse
import json
import re
import subprocess
import wave
from pathlib import Path

import numpy as np

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--master', type=Path, required=True)
p.add_argument('--captions', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--speed', type=float, default=1.15)
a = p.parse_args()
if not 1 <= a.speed <= 2:
    p.error('Speed must be between 1 and 2')
if a.master.resolve() == a.output.resolve():
    p.error('Keep the silent master separate')
a.work.mkdir(parents=True, exist_ok=True)
a.output.parent.mkdir(parents=True, exist_ok=True)
probe = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                                'format=duration', '-of', 'json', str(a.master)])
duration = float(json.loads(probe)['format']['duration']) / a.speed
sr = 44100
audio = np.zeros((round(duration * sr), 2), dtype=np.float64)
beat = duration / 64  # sixteen four-beat bars, resolved to the video ending


def note(midi, start, length, gain, pan=0, soft=False):
    n = min(round(length * sr), len(audio) - round(start * sr))
    if n <= 0:
        return
    t = np.arange(n) / sr
    f = 440 * 2 ** ((midi - 69) / 12)
    tone = (np.sin(2 * np.pi * f * t) + .22 * np.sin(4 * np.pi * f * t)
            + .07 * np.sin(6 * np.pi * f * t))
    env = (1 - np.exp(-t / (.025 if soft else .006))) * np.exp(-t / (.6 if soft else .23))
    env *= np.minimum(1, (length - t) / .08).clip(0, 1)
    signal = tone * env * gain
    at = round(start * sr)
    audio[at:at+n, 0] += signal * np.sqrt((1-pan)/2)
    audio[at:at+n, 1] += signal * np.sqrt((1+pan)/2)


# Cmaj7 / Am7 / Fmaj7 / G6, soft keys, a sparse plucked melody and warm bass.
chords = [(60, 64, 67, 71), (57, 60, 64, 67), (53, 57, 60, 64), (55, 59, 62, 64)]
melodies = [(76, 79, 74, 76), (72, 76, 79, 76), (77, 76, 72, 69), (74, 71, 69, 67)]
for bar in range(16):
    chord = chords[bar % 4] if bar < 15 else chords[0]
    start = bar * 4 * beat
    for k, pitch in enumerate(chord):
        note(pitch, start + .025*k, 2*beat, .055, (k-1.5)*.25, True)
    note(chord[0]-12, start, 2*beat, .13, soft=True)
    if bar < 15:
        note(chord[0]-12, start+2*beat, 1.6*beat, .09, soft=True)
    for k, pitch in enumerate(melodies[bar % 4] if bar < 15 else (76, 72)):
        note(pitch, start + (k*.75+.5)*beat, beat, .07, (-1)**k*.25)

# Short stereo echoes keep the otherwise dry synthesis gentle.
dry = audio.copy()
for delay, gain in [(.12, .16), (.24, .09), (.37, .04)]:
    shift = round(delay*sr)
    audio[shift:] += dry[:-shift, ::-1] * gain
t = np.arange(len(audio)) / sr
audio *= (np.minimum(1, t/.65) * np.minimum(1, (duration-t)/1.5))[:, None]
peak = np.max(np.abs(audio))
if peak > .42:
    audio *= .42 / peak
wav = a.work/'kat-coffee-music.wav'
with wave.open(str(wav), 'wb') as f:
    f.setnchannels(2)
    f.setsampwidth(2)
    f.setframerate(sr)
    f.writeframes((audio*32767).astype('<i2').tobytes())
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                '-i', str(a.master), '-i', str(wav),
                '-vf', f'setpts=PTS/{a.speed},fps=30',
                '-map', '0:v:0', '-map', '1:a:0', '-t', str(duration),
                '-c:v', 'libx264', '-threads', '2', '-preset', 'slow', '-crf', '21',
                '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k',
                '-movflags', '+faststart', str(a.output)], check=True)


def retime(match):
    h, m, s = map(float, match.group().split(':'))
    ms = round((h*3600+m*60+s)*1000/a.speed)
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}.{ms%1000:03}'


for vtt in a.captions.glob('kat-ios-demo.*.vtt'):
    (a.output.parent/vtt.name).write_text(re.sub(r'\d{2}:\d{2}:\d{2}\.\d{3}', retime, vtt.read_text()))
print(json.dumps({'duration': duration, 'speed': a.speed, 'bytes': a.output.stat().st_size,
                  'musicPeakDBFS': float(20*np.log10(np.max(np.abs(audio)))),
                  'musicRMSDBFS': float(20*np.log10(np.sqrt(np.mean(audio**2))))}, indent=2))
