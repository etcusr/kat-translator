#include "WhisperCancellation.h"
#include <stdatomic.h>
#include <stdlib.h>
struct wt_cancel_flag { atomic_bool cancelled; };
wt_cancel_flag * wt_cancel_create(void) {
    wt_cancel_flag * flag = malloc(sizeof(*flag));
    if (flag) atomic_init(&flag->cancelled, false);
    return flag;
}
void wt_cancel_set(wt_cancel_flag * flag) { if (flag) atomic_store(&flag->cancelled, true); }
bool wt_abort(void * ptr) { return ptr && atomic_load(&((wt_cancel_flag *)ptr)->cancelled); }
void wt_cancel_free(wt_cancel_flag * flag) { free(flag); }
