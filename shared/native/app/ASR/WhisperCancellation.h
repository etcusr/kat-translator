#pragma once
#include <stdbool.h>
typedef struct wt_cancel_flag wt_cancel_flag;
wt_cancel_flag * wt_cancel_create(void);
void wt_cancel_set(wt_cancel_flag * flag);
bool wt_abort(void * flag);
void wt_cancel_free(wt_cancel_flag * flag);
