#!/usr/bin/env python3
"""Compose a short promo from real simulator footage. Never generates app results.
Requires ffmpeg, Pillow, a source recording and an explicit edit-decision JSON.
"""
import argparse, json, math, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[3]
W,H,FPS=1280,720,30
LIME=(206,250,51);INK=(242,244,236);MUTED=(173,182,162);BG=(10,12,9)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--recording',type=Path,required=True)
p.add_argument('--edit',type=Path,required=True)
p.add_argument('--work',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.work.mkdir(parents=True,exist_ok=True);a.output.parent.mkdir(parents=True,exist_ok=True)
edit=json.loads(a.edit.read_text())
fontroot=Path('/System/Library/Fonts/Supplemental')
def font(n,bold=False):return ImageFont.truetype(str(fontroot/('Arial Bold.ttf' if bold else 'Arial.ttf')),n)
logo=Image.open(ROOT/'site/assets/brand/kat.png').convert('RGBA')
def rounded_logo(size):
 im=logo.resize((size,size),Image.Resampling.LANCZOS);mask=Image.new('L',(size,size));ImageDraw.Draw(mask).rounded_rectangle((0,0,size,size),radius=size*.24,fill=255);im.putalpha(mask);return im

def text(draw,xy,s,size=28,fill=INK,bold=False,spacing=12):draw.multiline_text(xy,s,font=font(size,bold),fill=fill,spacing=spacing)
def background():
 im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
 for r in (220,300,380):d.ellipse((940-r,355-r,940+r,355+r),outline=(33,42,22),width=1)
 im.paste(rounded_logo(46),(50,35),rounded_logo(46));text(d,(110,43),'Kat translator',23,bold=True)
 text(d,(50,675),'iPhone Simulator · actual app · edited sequence',16,MUTED)
 return im

def ff(args):subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*args],check=True)
def animate_card(path,closing=False):
 duration=3.2 if not closing else 4
 proc=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{W}x{H}','-framerate',str(FPS),'-i','-','-an','-c:v','libx264','-threads','2','-preset','fast','-crf','20','-pix_fmt','yuv420p',str(path)],stdin=subprocess.PIPE)
 for frame in range(round(duration*FPS)):
  t=frame/FPS;im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
  # A playful path into the frame: the real brand icon, not an imitation app screen.
  s=min(1,t/.9);ease=1-(1-s)**3
  x=int(-210+(290 if not closing else 300)*ease);y=int(214-18*math.sin(t*4)*min(1,t))
  icon=rounded_logo(170);im.paste(icon,(x,y),icon)
  for i in range(4):
   if t>0.18*i:
    px=40+i*58;py=475+math.sin(i)*13
    d.ellipse((px,py,px+16,py+20),fill=(60,73,29))
    for dx,dy in [(-3,-9),(7,-15),(17,-9)]:d.ellipse((px+dx,py+dy,px+dx+7,py+dy+8),fill=(60,73,29))
  tx=int(400+70*(1-ease));alpha=min(1,max(0,(t-.35)/.5))
  shade=tuple(int(BG[i]+(INK[i]-BG[i])*alpha) for i in range(3))
  text(d,(tx,205),'Small cat.\nBig conversations.' if not closing else 'Less language barrier.\nMore coffee.',62,shade,True,16)
  if t>1:
   text(d,(tx,405),'Meet Kat.' if not closing else 'Kat translator',34,LIME,True)
   text(d,(tx,467),'Offline translation. On your device.' if not closing else 'Download your models. Take your words along.',25,MUTED)
  if closing:text(d,(tx,580),'iPhone · Apple Silicon Mac · Android',19,MUTED)
  proc.stdin.write(im.tobytes())
 proc.stdin.close();assert proc.wait()==0
 return duration
# Simulator recordings use variable frame rate and omit unchanged frames. Normalize
# before seeking so a cut inside a static interval keeps the correct visible frame.
normalized=a.work/'source-cfr.mp4'
ff(['-i',str(a.recording),'-vf',f'fps={FPS}', '-an','-c:v','libx264','-threads','2','-preset','fast','-crf','18','-pix_fmt','yuv420p',str(normalized)])
segments=[];durations=[]
intro=a.work/'00-intro.mp4';durations.append(animate_card(intro));segments.append(intro)
for i,scene in enumerate(edit['scenes'],1):
 start=float(scene['start']);end=float(scene['end']);duration=end-start
 if start<0 or duration<=0:raise ValueError('Invalid cut')
 base=background();d=ImageDraw.Draw(base)
 text(d,(55,150),f'0{i} / '+scene['label'],18,LIME,True)
 text(d,(55,210),scene['title'],55,INK,True,12)
 text(d,(55,415),scene['body'],25,MUTED,False,10)
 if scene.get('note'):text(d,(55,575),scene['note'],18,LIME)
 # Screen surround does not change or retouch the captured app pixels.
 d.rounded_rectangle((828,47,1120,679),radius=32,fill=(3,4,3),outline=(65,76,43),width=3)
 basefile=a.work/f'{i:02}-base.png';base.save(basefile)
 out=a.work/f'{i:02}-scene.mp4'
 # 1x playback; only explicit between-scene cuts and dissolves shorten the recording.
 filters=f'[0:v]fps={FPS},format=yuv420p,settb=1/{FPS}[bg];[1:v]scale=276:600:force_original_aspect_ratio=decrease,pad=276:600:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps={FPS},setpts=PTS-STARTPTS,settb=1/{FPS}[phone];[bg][phone]overlay=836:64:shortest=1,format=yuv420p[v]'
 ff(['-loop','1','-framerate',str(FPS),'-i',str(basefile),'-ss',str(start),'-t',str(duration),'-i',str(normalized),'-filter_complex_threads','1','-filter_complex',filters,'-map','[v]','-t',str(duration),'-an','-c:v','libx264','-threads','2','-preset','fast','-crf','20',str(out)])
 segments.append(out);durations.append(duration)
end=a.work/'99-outro.mp4';durations.append(animate_card(end,True));segments.append(end)
inputs=[]
for segment in segments:inputs+=['-i',str(segment)]
filters=[];offset=durations[0];last='0:v';transition=.4
for i in range(1,len(segments)):
 offset-=transition;label=f'x{i}'
 filters.append(f'[{last}][{i}:v]xfade=transition={"slideleft" if i in (1,len(segments)-1) else "fade"}:duration={transition}:offset={offset:.6f}[{label}]')
 last=label;offset+=durations[i]
ff([*inputs,'-filter_complex_threads','1','-filter_complex',';'.join(filters),'-map',f'[{last}]','-an','-c:v','libx264','-threads','2','-preset','slow','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',str(a.output)])
(a.work/'timeline.json').write_text(json.dumps({'durations':durations,'transition':transition,'total':offset,'playbackSpeed':1,'source':str(a.recording.name)},indent=2)+'\n')
print(f'Created {a.output}: {offset:.2f}s, {a.output.stat().st_size:,} bytes')
