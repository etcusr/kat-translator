"""Offline OPUS/Metal worker. Isolated from Index's incompatible Python dependencies."""
import os
import sys
import json
import gc
from pathlib import Path


def request_input(source, target, text):
    tags = {"ru": "rus", "uk": "ukr", "be": "bel"}
    if source == "en" and target in tags:
        return "en-zle", ">>" + tags[target] + "<< " + text
    if source in tags and target == "en":
        return "zle-en", text
    raise ValueError("Unsupported OPUS direction")


def complete(ids, eos):
    return bool(ids) and len(ids) < 513 and ids[-1] == eos


class Engine:
    def __init__(self, directory):
        os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1",
                          HF_HUB_DISABLE_IMPLICIT_TOKEN="1", TOKENIZERS_PARALLELISM="false",
                          PYTORCH_ENABLE_MPS_FALLBACK="0", PYTORCH_MPS_FAST_MATH="0")
        import torch
        import sacremoses  # Require the same normalization as the benchmark.
        from transformers import MarianTokenizer, MarianMTModel
        self.torch, self.Model = torch, MarianMTModel
        torch.set_num_threads(4)
        torch.set_num_interop_threads(1)
        torch.manual_seed(0)
        if not torch.backends.mps.is_available():
            raise RuntimeError("Metal GPU unavailable")
        self.root = Path(directory)
        self.tokenizers = {d: MarianTokenizer.from_pretrained(self.root / d, local_files_only=True)
                           for d in ("en-zle", "zle-en")}
        self.direction, self.model = None, None

    def inputs(self, request):
        direction, text = request_input(request["source"], request["target"], request["text"])
        return direction, self.tokenizers[direction], text

    def count(self, request):
        _, tokenizer, text = self.inputs(request)
        return {"code": 0, "count": len(tokenizer(text, truncation=False).input_ids)}

    def run(self, request):
        direction, tokenizer, text = self.inputs(request)
        inputs = tokenizer(text, return_tensors="pt", truncation=False)
        if inputs.input_ids.shape[1] > 480:
            return {"code": 1}
        if self.direction != direction:
            self.model = None
            gc.collect()
            self.torch.mps.synchronize()
            self.torch.mps.empty_cache()
            model = self.Model.from_pretrained(self.root / direction, local_files_only=True,
                                              torch_dtype=self.torch.float16).to("mps").eval()
            if not all(p.device.type == "mps" and p.dtype == self.torch.float16 for p in model.parameters()):
                raise RuntimeError("OPUS must use Metal FP16")
            self.model, self.direction = model, direction
        with self.torch.inference_mode():
            ids = self.model.generate(**inputs.to("mps"), num_beams=5,
                                      max_new_tokens=512, do_sample=False)[0].tolist()
        self.torch.mps.synchronize()
        if not complete(ids, self.model.config.eos_token_id):
            return {"code": 1}
        output = tokenizer.decode(ids, skip_special_tokens=True).strip()
        if not output:
            raise RuntimeError("Empty OPUS translation")
        return {"code": 0, "text": output, "device": "mps:0", "precision": "float16"}


def main():
    engine = Engine(sys.argv[1])
    print(json.dumps({"code": 0, "ready": True, "device": "mps:0"}), flush=True)
    while line := sys.stdin.buffer.readline(1024 * 1024):
        try:
            if not line.endswith(b"\n"):
                raise ValueError("Oversized request")
            request = json.loads(line)
            command = request["command"]
            if command not in ("count", "run"):
                raise ValueError("Unknown command")
            response = getattr(engine, command)(request)
        except Exception as error:
            # Do not retain tracebacks/model tensors between requests or return source text in logs.
            print(type(error).__name__, file=sys.stderr, flush=True)
            response = {"code": -1}
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
