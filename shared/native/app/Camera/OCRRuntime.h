#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *ot_ocr_load(const char *path);
void ot_ocr_free(void *handle);
int ot_ocr_height(void *handle);
// Input is BGR normalized [-1,1], planar 3 x height x width. Returns CTC ids, including blanks.
int ot_ocr_run(void *handle, const float *input, int width, int *ids, int capacity);
#ifdef __cplusplus
}
#endif
