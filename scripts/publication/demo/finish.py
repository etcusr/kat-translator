#!/usr/bin/env python3
"""Speed up the silent master and add an original, synthesized instrumental bed.

Requires NumPy and FFmpeg. Always use the 1x silent master,
not a previous finished export. No recordings, samples or external music assets.
"""
import argparse
import json
import subprocess
import wave
from pathlib import Path

import numpy as np

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--master', type=Path, required=True)
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


# A through-arranged miniature: two-bar opening, theme, contrasting arpeggios,
# varied return and a two-bar cadence. No repeated four-bar backing loop.
chords = [
    (60,64,67,71), (55,62,67,69),
    (60,64,67,71), (57,60,64,67), (53,57,60,64), (55,59,62,69),
    (52,59,64,67), (57,60,64,71), (50,57,60,65), (55,59,62,67),
    (53,60,64,69), (52,59,62,67), (57,60,64,69), (50,57,60,65),
    (55,59,62,65), (48,55,60,64),
]
# Per-bar (beat offset, pitch, length in beats); rests are intentional.
melodies = [
    [(1,76,1.5)], [(0.5,79,1),(2.5,74,1)],
    [(0,76,.6),(1,79,.8),(2.5,83,1)],
    [(.5,81,1),(2,79,.6),(3,76,.7)],
    [(0,77,1),(1.5,76,.6),(3,72,.8)],
    [(.5,74,.8),(2,71,1.5)],
    [(1,71,1.5)], [(0,72,.7),(2.5,76,1)],
    [(.5,74,1),(2,77,1.5)], [(1,79,2)],
    [(0,81,.7),(1,79,.5),(2,76,.8),(3.25,77,.5)],
    [(.5,79,1),(2,74,.7),(3,71,.7)],
    [(0,72,.7),(1.5,76,.6),(2.5,81,1)],
    [(.5,77,.7),(1.5,74,.7),(3,72,.8)],
    [(0,71,1.5),(2,74,1.4)], [(0,72,3.5)],
]
for bar in range(16):
    chord = chords[bar]
    start = bar * 4 * beat
    if 6 <= bar < 10:
        # Thin the texture and move the harmony through the stereo field.
        for k in range(6):
            note(chord[k % 4], start+k*.5*beat, beat, .04, (k%3-1)*.35)
    else:
        for k, pitch in enumerate(chord):
            note(pitch, start+.04*k, (3 if bar>=14 else 2)*beat,
                 .032 if bar<2 else .05, (k-1.5)*.25, True)
    if bar >= 2:
        note(chord[0]-12, start, 2.5*beat, .11, soft=True)
    if 2 <= bar < 6 or 10 <= bar < 14:
        note(chord[0]-5, start+2.5*beat, beat, .06, soft=True)
    for k, (offset, pitch, length) in enumerate(melodies[bar]):
        note(pitch, start+offset*beat, length*beat, .07, (-1)**k*.2,
             soft=bar>=14)

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


print(json.dumps({'duration': duration, 'speed': a.speed, 'bytes': a.output.stat().st_size,
                  'musicPeakDBFS': float(20*np.log10(np.max(np.abs(audio)))),
                  'musicRMSDBFS': float(20*np.log10(np.sqrt(np.mean(audio**2))))}, indent=2))
