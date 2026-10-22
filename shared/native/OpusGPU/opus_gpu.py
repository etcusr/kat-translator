"""Offline OPUS/Metal worker. Isolated from Index's incompatible Python dependencies."""
import os
import sys
import json
import queue
import threading
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
        from transformers import MarianTokenizer, MarianMTModel, StoppingCriteria, StoppingCriteriaList
        self.torch, self.Model = torch, MarianMTModel
        engine = self

        class Cancelled(StoppingCriteria):
            def __call__(self, input_ids, scores, **kwargs):
                return torch.full((input_ids.shape[0],), engine.stopped(), dtype=torch.bool, device=input_ids.device)
        self.stopping = StoppingCriteriaList([Cancelled()])
        self.stopped = lambda: False
        torch.set_num_threads(4)
        torch.set_num_interop_threads(1)
        torch.manual_seed(0)
        if not torch.backends.mps.is_available():
            raise RuntimeError("Metal GPU unavailable")
        self.root = Path(directory)
        self.tokenizers = {d: MarianTokenizer.from_pretrained(self.root / d, local_files_only=True)
                           for d in ("en-zle", "zle-en")}
        self.models = {}

    def inputs(self, request):
        direction, text = request_input(request["source"], request["target"], request["text"])
        return direction, self.tokenizers[direction], text

    def model_for(self, direction):
        # Both directions stay resident (~0.5 GB each): a RU<->EN dialogue switches every turn,
        # and reloading cost ~1.3 s per turn.
        if direction not in self.models:
            self.models[direction] = self.load(direction)
        return self.models[direction]

    def load(self, direction):
        model = self.Model.from_pretrained(self.root / direction, local_files_only=True,
                                           torch_dtype=self.torch.float16).to("mps").eval()
        if not all(p.device.type == "mps" and p.dtype == self.torch.float16 for p in model.parameters()):
            raise RuntimeError("OPUS must use Metal FP16")
        return model

    def count(self, request):
        _, tokenizer, text = self.inputs(request)
        return {"code": 0, "count": len(tokenizer(text, truncation=False).input_ids)}

    def run(self, request):
        direction, tokenizer, text = self.inputs(request)
        inputs = tokenizer(text, return_tensors="pt", truncation=False)
        if inputs.input_ids.shape[1] > 480:
            return {"code": 1}
        model = self.model_for(direction)
        if self.stopped():
            return {"code": 2}
        with self.torch.inference_mode():
            ids = model.generate(**inputs.to("mps"), num_beams=5, max_new_tokens=512, do_sample=False,
                                 stopping_criteria=self.stopping)[0].tolist()
        self.torch.mps.synchronize()
        if self.stopped():
            return {"code": 2}
        if not complete(ids, model.config.eos_token_id):
            return {"code": 1}
        output = tokenizer.decode(ids, skip_special_tokens=True).strip()
        if not output:
            raise RuntimeError("Empty OPUS translation")
        return {"code": 0, "text": output, "device": "mps:0", "precision": "float16"}


class Requests:
    """Reads stdin on its own thread, so a cancel line reaches a running generation.

    Request ids grow monotonically: cancelling id N stops request N (also one not started yet),
    and a late cancel for a finished request cannot stop a later one."""
    def __init__(self, stream):
        self.lines, self.cancelled = queue.Queue(), 0
        threading.Thread(target=self.read, args=(stream,), daemon=True).start()

    def read(self, stream):
        while line := stream.readline(1024 * 1024):
            try:
                request = json.loads(line) if line.endswith(b"\n") else None
            except ValueError:
                request = None
            if isinstance(request, dict) and request.get("command") == "cancel" and type(request.get("id")) is int:
                self.cancelled = max(self.cancelled, request["id"])
            else:
                self.lines.put(line)
        self.lines.put(None)


def serve(engine, stdin, stdout):
    requests = Requests(stdin)
    print(json.dumps({"code": 0, "ready": True, "device": "mps:0"}), file=stdout, flush=True)
    while (line := requests.lines.get()) is not None:
        identifier = None
        try:
            if not line.endswith(b"\n"):
                raise ValueError("Oversized request")
            request = json.loads(line)
            command, identifier = request["command"], request["id"]
            if command not in ("count", "run") or type(identifier) is not int:
                raise ValueError("Unknown command")
            engine.stopped = lambda: requests.cancelled >= identifier
            response = getattr(engine, command)(request)
        except Exception as error:
            # Do not retain tracebacks/model tensors between requests or return source text in logs.
            print(type(error).__name__, file=sys.stderr, flush=True)
            response = {"code": -1}
        if type(identifier) is int:
            response["id"] = identifier
        print(json.dumps(response, ensure_ascii=False), file=stdout, flush=True)


def main():
    serve(Engine(sys.argv[1]), sys.stdin.buffer, sys.stdout)


if __name__ == "__main__":
    main()
