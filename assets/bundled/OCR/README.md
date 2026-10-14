# Offline OCR provenance

Open recognizers: PP-OCRv5 mobile English and East Slavic (RU) recognizers converted to ONNX by `monkt/paddleocr-onnx`, pinned revision `7b02d0a30a07ba2b92ad1ff5a8941ae2c633de65`.

- Pinned artifacts/model card: https://huggingface.co/monkt/paddleocr-onnx/tree/7b02d0a30a07ba2b92ad1ff5a8941ae2c633de65
- Original models/docs: https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv5/PP-OCRv5_multi_languages.en.md
- Dictionary sources at that exact conversion revision: `languages/eslav/dict.txt`, `languages/english/dict.txt`.
- The converted model card declares `apache-2.0`. `LICENSE.txt` is the Apache 2.0 text from PaddleOCR v3.0.3 (`https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/refs/tags/v3.0.3/LICENSE`); the conversion repository did not contain a standalone LICENSE file at the pinned revision. This is third-party conversion, not an official Paddle ONNX release.

Weights download only on user request; size and SHA-256 are in `App/Models/ModelCatalog.swift`. Dictionary JSON is bundled and derived exactly as `[blank] + splitlines(dict.txt) + [space]` for CTC decoding. Model/dictionary hashes and input convention are recorded in `Dependencies/runtime.lock.json`. No models, photos or recognized private text are committed.

The app asks Vision for supported recognition languages on the actual OS. If source is supported, use `VNRecognizeTextRequest`. Otherwise (or when forced in the camera UI) use `VNDetectTextRectanglesRequest` to locate lines, then run local ONNX recognition. Thus fallback replaces language recognition, not region detection. Only RU and EN are enabled in this app iteration; a language listed by a model repository is not automatically enabled in the product.

Reproduction: `scripts/validation/run-ocr-probe.sh` uses a local Python environment with numpy, Pillow and onnxruntime, and the downloaded pinned ONNX files. It builds the actual C bridge then the actual Swift HybridOCR for macOS. This does not validate iOS preview geometry or speed.
