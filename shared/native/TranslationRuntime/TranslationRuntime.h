#ifndef OT_TRANSLATION_RUNTIME_H
#define OT_TRANSLATION_RUNTIME_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void *ot_mt_load(const char *path);
// Apple legacy defaults remain 4 threads, 99 GPU layers, flash attention enabled.
// Android selects its GPU profile explicitly; CPU remains available for control tests.
void *ot_mt_load_config(const char *path, int threads, int gpu_layers, int flash_attention);
// Returns required token count; writes only when capacity is sufficient.
int ot_mt_tokens(void *handle, const char *prefix, const char *text, const char *suffix, int *out, size_t capacity);
void ot_mt_free(void *handle);
void *ot_mt_flag_create(void);
void ot_mt_flag_cancel(void *flag);
void ot_mt_flag_free(void *flag);
int ot_mt_count(void *handle, const char *prefix, const char *text, const char *suffix);
// 0 success, 1 output/input limit, 2 cancelled, -1 invalid/backend error, -2 invalid logits.
// Copies the text generated so far by the running request (UTF-8, may end mid-sentence).
// Returns its byte length; writes only when capacity is sufficient, -1 for invalid arguments.
int ot_mt_partial(void *handle, char *out, size_t capacity);
int ot_mt_run(void *handle, const char *prefix, const char *text, const char *suffix, void *flag, char *out, size_t capacity, double *first_token_seconds);
#ifdef __cplusplus
}
#endif
#endif
