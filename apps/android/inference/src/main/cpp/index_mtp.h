#pragma once
#include <cstddef>
void *kat_mtp_load(const char *path,int threads,bool flash);
void kat_mtp_free(void *handle);
int kat_mtp_tokens(void *handle,const char *prefix,const char *text,const char *suffix,int *out,size_t capacity);
int kat_mtp_run(void *handle,const char *prefix,const char *text,const char *suffix,void *flag,char *out,size_t capacity,double *first,int *drafted,int *accepted);
