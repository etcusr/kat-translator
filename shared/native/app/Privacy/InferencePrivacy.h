#ifndef OT_INFERENCE_PRIVACY_H
#define OT_INFERENCE_PRIVACY_H
// Must succeed before the first ONNX/Sherpa call in this process.
int ot_prepare_inference_privacy(void);
#endif
