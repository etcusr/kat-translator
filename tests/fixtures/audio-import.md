# Audio import fixture

`audio-import.m4a` is a 5.014-second synthetic English recording generated on macOS with the installed Samantha system voice, converted to AAC with ffmpeg. It contains no user recording.

> Please bring two cups of tea to room twenty four. The meeting starts tomorrow at ten thirty.

Used by opt-in real ASR/MT integration checks on Mac (also validated on physical iPhone before the feature was restricted to desktop). Unit tests generate their own PCM/AAC waveforms in temporary files. The Mac file-picker test also uses an MP3 conversion at `.build/audio-import/import-voice.mp3`.
