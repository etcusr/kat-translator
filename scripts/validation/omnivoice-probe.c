#include "omnivoice.h"
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdlib.h>
#include <mach/mach.h>
static double seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static unsigned long long footprint(void){task_vm_info_data_t i;mach_msg_type_number_t n=TASK_VM_INFO_COUNT;return task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&i,&n)==KERN_SUCCESS?i.phys_footprint:0;}
static void wave(const char *path,struct ov_audio *a){FILE*f=fopen(path,"wb");unsigned int sr=a->sample_rate,nb=a->n_samples*2,chunk=36+nb,sz=16,br=sr*2;unsigned short one=1,bps=16,ba=2;fwrite("RIFF",1,4,f);fwrite(&chunk,4,1,f);fwrite("WAVEfmt ",1,8,f);fwrite(&sz,4,1,f);fwrite(&one,2,1,f);fwrite(&one,2,1,f);fwrite(&sr,4,1,f);fwrite(&br,4,1,f);fwrite(&ba,2,1,f);fwrite(&bps,2,1,f);fwrite("data",1,4,f);fwrite(&nb,4,1,f);for(int i=0;i<a->n_samples;i++){short x=(short)(fmaxf(-1,fminf(1,a->samples[i]))*32767);fwrite(&x,2,1,f);}fclose(f);}
static bool cancel_third_poll(void *data){return ++*(int *)data >= 3;}
int main(int argc,char**argv){
 if(argc==2){for(int i=0;i<ov_n_languages();i++)printf("%s\t%s\n",ov_language_id(i),ov_language_name(i));return 0;}
 if(argc!=6)return 64;
 struct ov_init_params init;ov_init_default_params(&init);init.model_path=argv[1];init.codec_path=argv[2];double start=seconds();
 struct ov_context*c=ov_init(&init);if(!c){fprintf(stderr,"%s\n",ov_last_error());return 1;}
 double load=seconds()-start;unsigned long long loaded=footprint();
 struct ov_tts_params p;ov_tts_default_params(&p);p.text=argv[4];p.lang=argv[3];p.chunk_duration_sec=5;p.chunk_threshold_sec=5;
 struct ov_audio a={0};
 if(getenv("OT_TEST_CANCEL")) {
  int polls=0;p.cancel=cancel_third_poll;p.cancel_user_data=&polls;start=seconds();
  enum ov_status cancelled=ov_synthesize(c,&p,&a);
  fprintf(stderr,"cancel-test status=%d polls=%d seconds=%.3f samples=%d\n",cancelled,polls,seconds()-start,a.n_samples);
  if(cancelled!=OV_STATUS_CANCELLED || polls!=3 || a.n_samples!=0 || seconds()-start>5)return 5;
  ov_audio_free(&a);p.cancel=NULL;p.cancel_user_data=NULL;
 }
 start=seconds();enum ov_status status=ov_synthesize(c,&p,&a);double elapsed=seconds()-start;
 if(status!=OV_STATUS_OK){fprintf(stderr,"%s\n",ov_last_error());ov_free(c);return 2;}
 double energy=0;for(int i=0;i<a.n_samples;i++){if(!isfinite(a.samples[i]))return 3;energy+=a.samples[i]*a.samples[i];}if(energy<.001)return 4;
 wave(argv[5],&a);printf("{\"language\":\"%s\",\"loadSeconds\":%.3f,\"synthesisSeconds\":%.3f,\"audioSeconds\":%.3f,\"loadedFootprint\":%llu,\"synthesisFootprint\":%llu,\"energy\":%.3f}\n",argv[3],load,elapsed,(double)a.n_samples/a.sample_rate,loaded,footprint(),energy);
 ov_audio_free(&a);ov_free(c);return 0;
}
