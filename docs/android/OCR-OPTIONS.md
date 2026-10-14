# Android OCR selection — 2026-10-12

User decision: Google ML Kit for its supported languages; open OCR for Russian.
Camera/image source selection is explicit: no automatic OCR language choice.
The user subsequently also removed speech language detection because its second
pass adds latency. Text translation language detection remains separate.

## Selected implementation

- Bundle all five ML Kit Text Recognition v2 script libraries (`16.0.1`) in the
  Android APK: Latin, Chinese, Japanese, Korean, Devanagari. This works on first
  use without downloading a Play Services module. No photos are sent to a
  recognition server. Android-only SDK assets are dependency-managed, not copied
  into Apple or shared model directories. The SDK itself is not open source.
- Route from explicit BCP-47 language and script, using Google's Supported and
  Experimental tables. Unsupported/unknown/Cyrillic tags never default to Latin.
  Experimental language coverage is not a claim of production quality. Mapped
  languages not explicitly included in the router remain unavailable.
- Russian uses the existing open PP-OCRv5 East Slavic mobile recognizer, unchanged
  weights and dictionary. Other unsupported languages need a validated recognizer;
  installing an unrelated model does not establish language coverage.
- Both backends produce normalized boxes and the existing paragraph grouping,
  frozen-image overlay, perspective/crop and translation flow.
- ML Kit owns a bitmap snapshot until its asynchronous task finishes. Cancellation
  suppresses publication and releases the app worker promptly; it does not claim
  to forcibly interrupt Google's internal computation.

## Open source candidates researched

| Candidate | Mobile integration | Assessment for this project |
|---|---|---|
| PP-OCRv5 mobile + existing ONNX Runtime | Already uses the current runtime and Russian recognizer | First candidate: compare a 4,819,576-byte mobile detector against the installed 88,030,804-byte server detector on identical Pixel inputs. |
| RapidOCR | PP-OCR model distribution plus ONNX/MNN/etc. wrappers | Useful model provenance and implementations; not an independent recognition model that automatically improves speed. |
| PP-OCRv5 + ncnn/Vulkan | Maintainer provides an Android example | Potential later runtime comparison. Example explicitly warns that small models may run slower on GPU. No measured Pixel superiority claimed. |
| Tesseract + tessdata_fast | Native runtime, integer small LSTM models, Russian available | Reasonable alternative to benchmark on documents; separate detector/layout/runtime integration required. No Pixel timing measured. |
| EasyOCR | Python/PyTorch-centric reference implementation | Broad language coverage; no demonstrated advantage for this Android integration. Not selected without a deployment/latency comparison. |

The current PP-OCR recognizer is already a mobile model. Only the detector is a
server-sized model. Newer version numbers and model size alone do not establish
accuracy or speed. Synthetic device corpus results must be reported separately
from real-photo quality and sustained live-camera performance.

## Sources

Checked official project documentation, not comparative blog rankings:
- https://developers.google.com/ml-kit/vision/text-recognition/v2/android
- https://developers.google.com/ml-kit/vision/text-recognition/v2/languages
- https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/pipeline_usage/OCR.en.md
- https://github.com/RapidAI/RapidOCR/blob/main/python/rapidocr/default_models.yaml
- https://github.com/nihui/ncnn-android-ppocrv5
- https://tesseract-ocr.github.io/tessdoc/Data-Files-in-tessdata_fast.html
- https://github.com/JaidedAI/EasyOCR

RapidOCR candidate source: ModelScope `RapidAI/RapidOCR`, version `v3.10.0`,
`onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx`.
SHA-256: `4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae`.
Research weight stored once under `model-store/research/ocr/`.
