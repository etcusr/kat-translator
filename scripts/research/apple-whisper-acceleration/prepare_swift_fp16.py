"""Add an opt-in FP16 activation experiment to the isolated upstream checkout."""
import argparse
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("checkout", type=Path)
a = p.parse_args()
path = a.checkout / "Sources/MLXAudioSTT/Models/Whisper/WhisperModel.swift"
text = path.read_text()
changes = {
    "let features = WhisperAudio.encoderFeatures(audio: audio, nMels: config.numMelBins)":
    """let rawFeatures = WhisperAudio.encoderFeatures(audio: audio, nMels: config.numMelBins)
        let features = ProcessInfo.processInfo.environment["BENCH_MLX_FP16"] == "1"
            ? rawFeatures.asType(.float16) : rawFeatures""",
    "sanitized[encPosKey] = whisperSinusoids(length: 1500, channels: conv2.shape[0])":
    """let positions = whisperSinusoids(length: 1500, channels: conv2.shape[0])
            sanitized[encPosKey] = ProcessInfo.processInfo.environment["BENCH_MLX_FP16"] == "1"
                ? positions.asType(conv2.dtype) : positions""",
}
for before, after in changes.items():
    assert text.count(before) == 1, "Unexpected upstream source; inspect before patching"
    text = text.replace(before, after)
path.write_text(text)
