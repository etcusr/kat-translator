#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <onnxruntime/onnxruntime_c_api.h>
#include "shared/native/app/Privacy/InferencePrivacy.h"
int main(int argc,char **argv) {
 if(argc!=5)return 2;
 void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
 if(!library){fprintf(stderr,"%s\n",dlerror());return 3;}
 const OrtApiBase *(*base)(void)=dlsym(library,"OrtGetApiBase");
 Dl_info image;if(!base || !dladdr((void *)base,&image))return 4;
 char *address=image.dli_fbase;
 volatile unsigned char *disabled=(void *)(address+strtoull(argv[2],NULL,16));
 void *volatile *logger=(void *)(address+strtoull(argv[3],NULL,16));
 void *volatile *manager=(void *)(address+strtoull(argv[4],NULL,16));
 if(*logger || *manager){fprintf(stderr,"Telemetry initialized before first API call\n");return 5;}
 if(!ot_prepare_inference_privacy())return 6;
 const OrtApi *api=base()->GetApi(17);OrtEnv *env=NULL;
 OrtStatus *status=api->CreateEnv(ORT_LOGGING_LEVEL_FATAL,"kat-privacy-probe",&env);
 if(status){fprintf(stderr,"%s\n",api->GetErrorMessage(status));api->ReleaseStatus(status);return 7;}
 printf("after CreateEnv: disabled=%d logger_null=%d manager_null=%d\n",*disabled,!*logger,!*manager);
 int valid=*disabled && !*logger && !*manager;
 api->ReleaseEnv(env);dlclose(library);return valid?0:8;
}
