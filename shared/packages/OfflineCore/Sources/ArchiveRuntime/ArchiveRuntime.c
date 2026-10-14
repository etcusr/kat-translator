#include "ArchiveRuntime.h"
#include <stdio.h>
#include <stdlib.h>
#include <bzlib.h>
typedef struct { FILE *file; BZFILE *bz; int ended; } Reader;
void *ot_bz_open(const char *path) {
    Reader *r = calloc(1, sizeof(Reader)); if (!r) return NULL;
    r->file = fopen(path, "rb"); if (!r->file) { free(r); return NULL; }
    int error; r->bz = BZ2_bzReadOpen(&error, r->file, 0, 0, NULL, 0);
    if (error != BZ_OK) { fclose(r->file); free(r); return NULL; } return r;
}
int ot_bz_read(void *handle, void *buffer, int count) {
    Reader *r = handle; if (r->ended) return 0;
    int error; int n = BZ2_bzRead(&error, r->bz, buffer, count);
    if (error == BZ_STREAM_END) r->ended = 1;
    else if (error != BZ_OK) return -1;
    return n;
}
void ot_bz_close(void *handle) { if (!handle) return; Reader *r = handle; int error; BZ2_bzReadClose(&error, r->bz); fclose(r->file); free(r); }
