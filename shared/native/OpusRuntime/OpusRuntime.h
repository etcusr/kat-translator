#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define OT_OPUS_API __attribute__((visibility("default")))
// The caller serializes context access. Only the independent cancellation flag is thread-safe.
OT_OPUS_API void *ot_opus_load(const char *package_path);
OT_OPUS_API void ot_opus_free(void *context);
OT_OPUS_API void *ot_opus_flag_create(void);
OT_OPUS_API void ot_opus_flag_cancel(void *flag);
OT_OPUS_API void ot_opus_flag_free(void *flag);
OT_OPUS_API const char *ot_opus_last_error(void);
OT_OPUS_API int ot_opus_count(void *context, const char *text, const char *source, const char *target);
OT_OPUS_API int ot_opus_prepare(void *context, const char *source, const char *target, void *flag);
// 0: success, 1: input/output limit, 2: cancelled, -1: error. Never returns a truncated success.
OT_OPUS_API int ot_opus_run(void *context, const char *text, const char *source, const char *target,
                           void *flag, char *output, size_t capacity);
// Catalog-driven API: direction is a package subdirectory such as "zle-zlw"; marker is the
// model's target label (for example ">>pol<<") or "" for single-target models.
OT_OPUS_API int ot_opus_count_direction(void *context, const char *text, const char *direction, const char *marker);
OT_OPUS_API int ot_opus_prepare_direction(void *context, const char *direction, void *flag);
OT_OPUS_API int ot_opus_run_direction(void *context, const char *text, const char *direction, const char *marker,
                                      void *flag, char *output, size_t capacity);
#ifdef __cplusplus
}
#endif
