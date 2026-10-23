# Demo music alternatives — 23 October 2026

Two additional original synthesized arrangements for selection. The currently selected landing-page video is unchanged. Both alternatives use exactly the same compressed video stream, duration 33.478 s, and no subtitle tracks. Music contains no external samples or recordings; composition and synthesis source are part of the repository under its license.

- **Playful:** D-major plucked strings, warm bass, light brushed rhythm, sparse breaks and a resolving ending.
- **Airy:** slower F-major/Lydian harmony, sustained soft pads, bell answers, spacious echoes; no percussion.

Files: `site/assets/video/options/{playful,airy}.{mp3,mp4}`. MP3s are standalone music previews; MP4s let the owner assess the same arrangements with the montage. Neither option is selected automatically. Generation: `scripts/publication/demo/music_options.py --video <current-video> --work <ignored-directory> --output <options-directory>` (NumPy + FFmpeg).

Checks: both MP4s and MP3s decode fully; compressed video SHA-256 matches the selected video in both cases. Music uses fade-in/out, target −27 dBFS RMS and a −6 dBFS peak ceiling before encoding. Musical preference remains for owner selection. No physical-device/app/model changes, deployment, push or Store action.

Export metadata:

```json
[
  {
    "name": "playful",
    "videoBytes": 1331062,
    "sha256": "59a80dff71c4a689dc3334bcca2197c4e4eb19b93758717d4801f74200828c1f"
  },
  {
    "name": "airy",
    "videoBytes": 1334973,
    "sha256": "e80e67faa9d9062f2a20bae8f0ef63e8e064379661baa2bb33c3d07d3bbbb699"
  }
]
```
