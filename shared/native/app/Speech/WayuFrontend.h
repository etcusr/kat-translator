#pragma once
#include <stdint.h>
// Initialize once, then call on the synthesis queue. All Python code is bundled.
int ot_wayu_python_init(const char *bundle_path);
int ot_wayu_frontend_init(const char *bundle_path);
int ot_wayu_frontend_tokens(const char *text, int64_t *tokens, int capacity);
int ot_wayu_frontend_style(const char *pack_path, const char *voice, int length, float *style);
