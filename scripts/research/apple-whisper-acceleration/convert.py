"""Convert the exact production F16 GGML weights, without downloading another checkpoint."""
import argparse
import importlib.util
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.dont_write_bytecode = True


def read_ggml(path):
    with Path(path).open("rb") as f:
        values = struct.unpack("<12i", f.read(48))
        assert values[0] == 0x67676D6C and values[-1] == 1, "Expected legacy F16 GGML"
        names = ["n_vocab", "n_audio_ctx", "n_audio_state", "n_audio_head",
                 "n_audio_layer", "n_text_ctx", "n_text_state", "n_text_head",
                 "n_text_layer", "n_mels"]
        config = dict(zip(names, values[1:-1]))
        a, b = struct.unpack("<2i", f.read(8))
        f.seek(a * b * 4, 1)
        count, = struct.unpack("<i", f.read(4))
        for _ in range(count):
            length, = struct.unpack("<i", f.read(4))
            f.seek(length, 1)
        weights = {}
        while header := f.read(12):
            dims, length, dtype = struct.unpack("<3i", header)
            shape = struct.unpack(f"<{dims}i", f.read(4 * dims))[::-1]
            name = f.read(length).decode()
            assert dtype in (0, 1), (name, dtype)
            tensor = np.fromfile(f, dtype="<f4" if dtype == 0 else "<f2",
                                 count=int(np.prod(shape))).reshape(shape)
            if name in ("encoder.conv1.bias", "encoder.conv2.bias"):
                tensor = tensor.reshape(-1)
            weights[name] = tensor
    return config, weights


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["mlx", "coreml"])
    p.add_argument("source", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--whisper-source", type=Path)
    args = p.parse_args()
    config, weights = read_ggml(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.mode == "mlx":
        args.output.mkdir(exist_ok=True)
        converted = {}
        for name, tensor in weights.items():
            if name == "encoder.positional_embedding":
                # mlx-whisper computes the same sinusoidal positional encoding.
                continue
            name = name.replace(".mlp.0.", ".mlp1.").replace(".mlp.2.", ".mlp2.")
            if name in ("encoder.conv1.weight", "encoder.conv2.weight"):
                tensor = tensor.transpose(0, 2, 1)
            converted[name] = tensor.astype(np.float16)
        np.savez(args.output / "weights.npz", **converted)
        (args.output / "config.json").write_text(json.dumps(config, indent=2))
        print(f"Converted {len(converted)} tensors to MLX F16", flush=True)
    else:
        import torch
        torch.set_num_threads(2)
        spec = importlib.util.spec_from_file_location(
            "upstream_coreml", args.whisper_source / "models/convert-whisper-to-coreml.py")
        upstream = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(upstream)
        # Use upstream ANE architecture and hooks, with the exact GGML encoder weights.
        encoder = upstream.AudioEncoderANE(
            config["n_mels"], config["n_audio_ctx"], config["n_audio_state"],
            config["n_audio_head"], config["n_audio_layer"])
        encoder._register_load_state_dict_pre_hook(upstream.linear_to_conv2d_map)
        state = {k.removeprefix("encoder."): torch.from_numpy(v.copy())
                 for k, v in weights.items() if k.startswith("encoder.")}
        encoder.load_state_dict(state, strict=True)
        del weights, state
        from whisper.model import ModelDimensions
        with torch.no_grad():
            model = upstream.convert_encoder(ModelDimensions(**config), encoder, quantize=True)
        model.save(str(args.output))
        print(f"Saved {args.output}", flush=True)


if __name__ == "__main__":
    main()
