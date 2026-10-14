#include "WayuSpeechRuntime.h"
#include "../ASR/WhisperCancellation.h"
#include <onnxruntime/onnxruntime_c_api.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include "../../Wayu/WayuSourceParameters.h"
// Adapted from kunato/wayu-kokoro-thai-v1 (50d7f60), Apache-2.0.
// Phase accumulation uses double precision as required by the reference exporter.
typedef struct { const OrtApi *api; OrtEnv *env; OrtSession *sessions[3]; OrtMemoryInfo *memory; } Wayu;
static int ok(Wayu *c, OrtStatus *s) {
    if(!s)return 1;
    fprintf(stderr,"Wayu: %s\n",c->api->GetErrorMessage(s));c->api->ReleaseStatus(s);return 0;
}
void ot_wayu_free(void *handle) {
    Wayu *c=handle;if(!c)return;
    for(int i=0;i<3;i++)if(c->sessions[i])c->api->ReleaseSession(c->sessions[i]);
    if(c->memory)c->api->ReleaseMemoryInfo(c->memory);
    if(c->env)c->api->ReleaseEnv(c->env);free(c);
}
void *ot_wayu_load(const char *prosody,const char *curves,const char *decoder) {
    Wayu *c=calloc(1,sizeof(*c));if(!c)return NULL;
    c->api=OrtGetApiBase()->GetApi(17);if(!c->api){free(c);return NULL;}
    OrtSessionOptions *opt=NULL;
    if(!ok(c,c->api->CreateEnv(ORT_LOGGING_LEVEL_ERROR,"wayu",&c->env)) ||
       !ok(c,c->api->DisableTelemetryEvents(c->env)) || !ok(c,c->api->CreateSessionOptions(&opt)) ||
       !ok(c,c->api->SetIntraOpNumThreads(opt,2)) || !ok(c,c->api->SetInterOpNumThreads(opt,1)) ||
       !ok(c,c->api->DisableCpuMemArena(opt)) ||
       !ok(c,c->api->CreateCpuMemoryInfo(OrtArenaAllocator,OrtMemTypeDefault,&c->memory)))goto fail;
    const char *paths[]={prosody,curves,decoder};
    for(int i=0;i<3;i++)if(!ok(c,c->api->CreateSession(c->env,paths[i],opt,&c->sessions[i])))goto fail;
    c->api->ReleaseSessionOptions(opt);return c;
fail:
    if(opt)c->api->ReleaseSessionOptions(opt);ot_wayu_free(c);return NULL;
}
static OrtValue *tensor(Wayu *c,void *data,size_t bytes,const int64_t *shape,size_t rank,ONNXTensorElementDataType type) {
    OrtValue *v=NULL;if(!ok(c,c->api->CreateTensorWithDataAsOrtValue(c->memory,data,bytes,shape,rank,type,&v)))return NULL;return v;
}
static int shape(Wayu *c,OrtValue *v,int64_t *dims,size_t rank,ONNXTensorElementDataType type) {
    OrtTensorTypeAndShapeInfo *i=NULL;size_t n=0;ONNXTensorElementDataType actual;
    if(!ok(c,c->api->GetTensorTypeAndShape(v,&i)))return 0;
    int valid=ok(c,c->api->GetDimensionsCount(i,&n)) && n==rank &&
      ok(c,c->api->GetTensorElementType(i,&actual)) && actual==type && ok(c,c->api->GetDimensions(i,dims,rank));
    c->api->ReleaseTensorTypeAndShapeInfo(i);return valid;
}
static void *data(Wayu *c,OrtValue *v) {void *p=NULL;if(!ok(c,c->api->GetTensorMutableData(v,&p)))return NULL;return p;}
static double uniform(uint64_t *s) {*s^=*s>>12;*s^=*s<<25;*s^=*s>>27;return (((*s*UINT64_C(2685821657736338717))>>11)+0.5)/9007199254740992.0;}
float *ot_wayu_harmonic(const float *f0,int frames,int noise_enabled) {
    if(!f0 || frames<1 || frames>3200)return NULL;
    const int n=frames*300, cols=n/5+1;
    double *phase=calloc((size_t)frames*9,sizeof(double));float *audio=malloc(n*sizeof(float));
    float *har=malloc((size_t)22*cols*sizeof(float));
    if(!phase||!audio||!har){free(phase);free(audio);free(har);return NULL;}
    for(int j=0;j<frames;j++)for(int h=0;h<9;h++){
        if(!isfinite(f0[j])){free(phase);free(audio);free(har);return NULL;}
        double r=(double)f0[j]*(h+1)/24000.0;r-=floor(r);
        phase[j*9+h]=(j?phase[(j-1)*9+h]:0)+r*2*M_PI*300;
    }
    uint64_t rng=1234;
    for(int j=0;j<n;j++){
        double pos=(j+0.5)/300.0-0.5;pos=fmax(0,fmin(frames-1,pos));int lo=(int)pos,hi=lo+1<frames?lo+1:lo;
        double w=pos-lo, merged=wayu_source_bias;
        int voiced=f0[j/300]>10;
        for(int h=0;h<9;h++){
            double p=phase[lo*9+h]*(1-w)+phase[hi*9+h]*w;
            double noise=noise_enabled?sqrt(-2*log(uniform(&rng)))*cos(2*M_PI*uniform(&rng)):0;
            double v=sin(p)*0.1*voiced+(voiced?0.003:0.1/3)*noise;
            merged+=v*wayu_source_weight[h];
        }
        audio[j]=(float)tanh(merged);
    }
    double cs[11][20],sn[11][20];
    for(int k=0;k<11;k++)for(int t=0;t<20;t++){cs[k][t]=cos(2*M_PI*k*t/20);sn[k][t]=-sin(2*M_PI*k*t/20);}
    for(int col=0;col<cols;col++)for(int k=0;k<11;k++){
        double re=0,im=0;
        for(int t=0;t<20;t++){
            int idx=col*5+t-10;if(idx<0)idx=-idx;if(idx>=n)idx=2*n-2-idx;
            double v=(double)audio[idx]*wayu_source_window[t];re+=v*cs[k][t];im+=v*sn[k][t];
        }
        har[k*cols+col]=(float)hypot(re,im);har[(k+11)*cols+col]=(float)atan2(im,re);
    }
    free(phase);free(audio);return har;
}
void ot_wayu_audio_free(float *p){free(p);}
float *ot_wayu_generate(void *handle,const int64_t *tokens,int count,const float *style,int *sample_count,void *flag) {
    if(sample_count)*sample_count=0;
    Wayu *c=handle;if(!c||!tokens||!style||!sample_count||count<3||count>502||wt_abort(flag))return NULL;
    for(int i=0;i<count;i++)if(tokens[i]<0||tokens[i]>=178)return NULL;
    for(int i=0;i<256;i++)if(!isfinite(style[i]))return NULL;
    OrtValue *in[3]={0},*pros[3]={0},*cur[2]={0},*en_v=NULL,*asr_v=NULL,*har_v=NULL,*acou_v=NULL,*wav=NULL;
    float *en=NULL,*asr=NULL,*har=NULL,*result=NULL;float speed=1;
    int64_t ts[]={1,count},ss[]={1,128},vs[]={1};
    in[0]=tensor(c,(void*)tokens,count*sizeof(int64_t),ts,2,ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64);
    in[1]=tensor(c,(void*)(style+128),128*sizeof(float),ss,2,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    in[2]=tensor(c,&speed,sizeof(float),vs,1,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    const char *pn[]={"input_ids","style_dur","speed"},*po[]={"pred_dur","d","t_en"};
    if(!in[0]||!in[1]||!in[2]||!ok(c,c->api->Run(c->sessions[0],NULL,pn,(const OrtValue *const*)in,3,po,3,pros))||wt_abort(flag))goto end;
    int64_t ds[1],es[3],as[3];
    if(!shape(c,pros[0],ds,1,ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64)||ds[0]!=count ||
       !shape(c,pros[1],es,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)||es[0]!=1||es[1]!=count||es[2]!=640 ||
       !shape(c,pros[2],as,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)||as[0]!=1||as[1]!=512||as[2]!=count)goto end;
    int64_t *dur=data(c,pros[0]);float *d=data(c,pros[1]),*t=data(c,pros[2]);if(!dur||!d||!t)goto end;
    int frames=0;
    for(int i=0;i<count;i++){if(dur[i]<1||dur[i]>1600 || frames+dur[i]>1600){*sample_count=-2;goto end;}frames+=(int)dur[i];}
    en=malloc((size_t)640*frames*sizeof(float));asr=malloc((size_t)512*frames*sizeof(float));if(!en||!asr)goto end;
    for(int i=0,col=0;i<count;i++)for(int rep=0;rep<dur[i];rep++,col++){
        for(int j=0;j<640;j++)en[j*frames+col]=d[i*640+j];
        for(int j=0;j<512;j++)asr[j*frames+col]=t[j*count+i];
    }
    int64_t en_shape[]={1,640,frames},asr_shape[]={1,512,frames};
    en_v=tensor(c,en,(size_t)640*frames*sizeof(float),en_shape,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    asr_v=tensor(c,asr,(size_t)512*frames*sizeof(float),asr_shape,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    const char *cn[]={"en","style_dur"},*co[]={"f0_curve","n_curve"};const OrtValue *ci[]={en_v,in[1]};
    if(!en_v||!asr_v||!ok(c,c->api->Run(c->sessions[1],NULL,cn,ci,2,co,2,cur))||wt_abort(flag))goto end;
    int64_t fs[2],ns[2];if(!shape(c,cur[0],fs,2,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)||fs[0]!=1||fs[1]!=frames*2 ||
        !shape(c,cur[1],ns,2,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)||ns[0]!=1||ns[1]!=fs[1])goto end;
    float *f0=data(c,cur[0]);har=ot_wayu_harmonic(f0,(int)fs[1],1);if(!har||wt_abort(flag))goto end;
    int64_t hs[]={1,22,frames*120+1};
    har_v=tensor(c,har,(size_t)22*hs[2]*sizeof(float),hs,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    acou_v=tensor(c,(void*)style,128*sizeof(float),ss,2,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    const char *dn[]={"asr","f0_curve","n_curve","style_acou","har"},*doo[]={"audio"};
    const OrtValue *di[]={asr_v,cur[0],cur[1],acou_v,har_v};
    if(!har_v||!acou_v||!ok(c,c->api->Run(c->sessions[2],NULL,dn,di,5,doo,1,&wav))||wt_abort(flag))goto end;
    OrtTensorTypeAndShapeInfo *info=NULL;size_t n=0;
    if(!ok(c,c->api->GetTensorTypeAndShape(wav,&info)))goto end;
    int valid=ok(c,c->api->GetTensorShapeElementCount(info,&n));c->api->ReleaseTensorTypeAndShapeInfo(info);
    if(!valid||!n||n>24000*40)goto end;
    float *audio=data(c,wav);if(!audio)goto end;
    for(size_t i=0;i<n;i++)if(!isfinite(audio[i]))goto end;
    result=malloc(n*sizeof(float));if(result){memcpy(result,audio,n*sizeof(float));*sample_count=(int)n;}
end:
    for(int i=0;i<3;i++){if(in[i])c->api->ReleaseValue(in[i]);if(pros[i])c->api->ReleaseValue(pros[i]);}
    for(int i=0;i<2;i++)if(cur[i])c->api->ReleaseValue(cur[i]);
    OrtValue *tmp[]={en_v,asr_v,har_v,acou_v,wav};for(int i=0;i<5;i++)if(tmp[i])c->api->ReleaseValue(tmp[i]);
    free(en);free(asr);free(har);return result;
}
