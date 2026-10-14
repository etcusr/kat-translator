#ifndef ARCHIVE_RUNTIME_H
#define ARCHIVE_RUNTIME_H
void *ot_bz_open(const char *path);
int ot_bz_read(void *reader, void *buffer, int count);
void ot_bz_close(void *reader);
#endif
