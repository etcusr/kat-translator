#pragma once
#if defined(OT_MACOS)
#include <stddef.h>
void *kat_mlx_load(const char *resources, const char *model_directory);
void kat_mlx_free(void *engine);
int kat_mlx_count(void *engine, const char *prefix, const char *text, const char *suffix);
void *kat_mlx_flag_create(void);
void kat_mlx_flag_cancel(void *flag);
void kat_mlx_flag_free(void *flag);
int kat_mlx_run(void *engine, const char *prefix, const char *text, const char *suffix,
                void *flag, char *output, size_t capacity, double *first_token);
// Called synchronously during generation; text is valid only for the callback.
// No callback can run after kat_mlx_run_stream returns, including on failure.
typedef void (*kat_mlx_partial_callback)(const char *text, void *user);
int kat_mlx_run_stream(void *engine, const char *prefix, const char *text, const char *suffix,
                      void *flag, char *output, size_t capacity, double *first_token,
                      kat_mlx_partial_callback partial, void *user);
#endif
