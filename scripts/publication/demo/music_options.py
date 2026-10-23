#!/usr/bin/env python3
"""Make two original instrumental alternatives without changing the selected video.

NumPy + FFmpeg; no external music or samples. Video is stream-copied for fair A/B.
"""
import argparse
import json
import subprocess
import wave
from pathlib import Path
import numpy as np

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--video', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
a.work.mkdir(parents=True, exist_ok=True)
info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
    'format=duration', '-of', 'json', str(a.video)]))
duration = float(info['format']['duration'])
sr = 44100
count = round(duration * sr)
rng = np.random.default_rng(23)


def add(buf, signal, start, pan=0):
    at = round(start * sr)
    n = min(len(signal), len(buf)-at)
    if n > 0:
        buf[at:at+n, 0] += signal[:n] * np.sqrt((1-pan)/2)
        buf[at:at+n, 1] += signal[:n] * np.sqrt((1+pan)/2)


def tone(buf, midi, start, length, gain, kind='pluck', pan=0):
    t = np.arange(round(length*sr))/sr
    f = 440*2**((midi-69)/12)
    if kind == 'pad':
        sound = (np.sin(2*np.pi*f*t)+.35*np.sin(2*np.pi*f*1.002*t)
                 +.12*np.sin(4*np.pi*f*t))
        env = np.minimum(1,t/.35)*np.minimum(1,(length-t)/.6)
    elif kind == 'bell':
        sound = np.sin(2*np.pi*f*t)+.3*np.sin(2*np.pi*f*2.01*t)*np.exp(-t*5)
        env = (1-np.exp(-t/.008))*np.exp(-t/.65)
    elif kind == 'bass':
        sound = np.sin(2*np.pi*f*t)+.16*np.sin(4*np.pi*f*t)
        env = (1-np.exp(-t/.012))*np.exp(-t/.3)
    else:
        sound = sum(np.sin(2*np.pi*f*k*t)*np.exp(-t*k*2)/k**1.4 for k in range(1,5))
        env = (1-np.exp(-t/.004))*np.exp(-t/.25)
    env *= np.minimum(1,(length-t)/.04).clip(0,1)
    add(buf, sound*env*gain, start, pan)


def playful():
    """Bouncy D-major pizzicato, brushed rhythm, changing short melodies."""
    buf = np.zeros((count,2)); beat = duration/64
    chords = [(62,66,69),(59,62,66),(55,59,62),(57,61,64),
              (62,66,69),(66,69,73),(64,67,71),(57,61,64),
              (55,59,62),(62,66,69),(59,62,66),(64,67,71),
              (55,59,62),(57,61,64),(57,62,64),(50,57,66)]
    tunes = [[(1,78),(2.5,81)],[(.5,78),(2,74)],[(0,79),(1.5,78),(3,74)],
             [(.5,76),(2.5,73)],[(0,78),(1,81),(2.5,86)],[(.5,85),(2,81),(3,78)],
             [(0,83),(1.5,79)],[(1,81),(2.5,76)],[(1.5,79)],[(.5,78),(3,74)],
             [(0,78),(1.5,81),(3,83)],[(.5,79),(2,76)],[(0,79),(1,78),(2.5,74)],
             [(.5,76),(2,73),(3,76)],[(0,74),(2,73)],[(0,74)]]
    for bar,chord in enumerate(chords):
        base=bar*4*beat
        sparse = bar in (0,1,8,9,15)
        for offset in ([0] if sparse else [.5,2.5]):
            for j,n in enumerate(chord):tone(buf,n,base+offset*beat+j*.018,beat,.075,pan=(j-1)*.35)
        tone(buf,chord[0]-12,base,beat*1.7,.15,'bass')
        if not sparse:
            tone(buf,chord[0]-5,base+2*beat,beat,.09,'bass')
            for off in (1,3):
                t=np.arange(round(.12*sr))/sr
                noise=rng.normal(0,1,len(t));noise=np.diff(noise,prepend=noise[0])
                add(buf,noise*np.exp(-t*65)*.014,base+off*beat,.3)
        for j,(offset,n) in enumerate(tunes[bar]):
            tone(buf,n,base+offset*beat,1.2*beat,.085,'pluck',(-1)**j*.2)
    return buf


def airy():
    """Slow, spacious F-major/Lydian colors, bell answers, no percussion."""
    buf=np.zeros((count,2));barlen=duration/8
    chords=[(53,60,64,69),(57,64,67,71),(55,62,65,69),(60,64,67,74),
            (50,57,60,64),(58,65,69,72),(60,65,67,74),(53,60,65,69)]
    melodies=[[(.25,81)],[(.15,83),(.6,79)],[(.3,77),(.7,74)],
              [(.15,76),(.5,79),(.78,84)],[(.25,81),(.65,76)],
              [(.1,77),(.45,81),(.75,84)],[(.2,79),(.6,76)],[(.05,77)]]
    for bar,chord in enumerate(chords):
        start=bar*barlen
        for j,n in enumerate(chord):
            tone(buf,n,start,barlen+.4,.045,'pad',(j-1.5)*.4)
        for j,(off,n) in enumerate(melodies[bar]):
            tone(buf,n,start+off*barlen,2,.075,'bell',(-1)**j*.4)
        if bar in (2,3,5,6):
            for j,n in enumerate(chord[1:]):
                tone(buf,n+12,start+(.2+j*.2)*barlen,1.3,.025,'bell',-.3+j*.3)
    return buf


for name, make in [('playful',playful),('airy',airy)]:
    buf=make();dry=buf.copy()
    for delay,gain in ([(.11,.12),(.23,.07)] if name=='playful' else [(.23,.22),(.46,.14),(.71,.08)]):
        shift=round(delay*sr);buf[shift:]+=dry[:-shift,::-1]*gain
    t=np.arange(count)/sr
    buf*=(np.minimum(1,t/.6)*np.minimum(1,(duration-t)/1.6))[:,None]
    buf*=10**(-27/20)/np.sqrt(np.mean(buf**2))
    peak=np.max(np.abs(buf))
    if peak>.5:buf*=.5/peak
    wav=a.work/f'{name}.wav'
    with wave.open(str(wav),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
        f.writeframes((buf*32767).astype('<i2').tobytes())
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libmp3lame',
                    '-b:a','160k',str(a.output/f'{name}.mp3')],check=True)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(a.video),'-i',str(wav),
                    '-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-b:a','128k',
                    '-t',str(duration),'-movflags','+faststart',str(a.output/f'{name}.mp4')],check=True)
    print(name, 'duration',duration,'peak dBFS',20*np.log10(np.max(np.abs(buf))))
