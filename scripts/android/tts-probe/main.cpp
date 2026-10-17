// Native VITS phase benchmark. Text is read from a caller-supplied file and never logged.
#include "sherpa-onnx/c-api/c-api.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
using Clock=std::chrono::steady_clock;
static double secs(Clock::time_point t){return std::chrono::duration<double>(Clock::now()-t).count();}
static int32_t cb(const float*,int32_t n,void *p){auto *s=(std::pair<Clock::time_point,double>*)p;if(s->second<0&&n>0)s->second=secs(s->first);return 1;}
int main(int argc,char**argv){
 if(argc<7){fprintf(stderr,"Usage: tts-probe model tokens espeak-data text-file threads repeats [wav-prefix]\n");return 2;}
 setenv("ORT_DISABLE_TELEMETRY","1",1);
 std::ifstream f(argv[4]);if(!f)return 2;std::string text((std::istreambuf_iterator<char>(f)),{});
 if(text.empty()||text.size()>80000||atoi(argv[5])<1||atoi(argv[5])>8||atoi(argv[6])<1||atoi(argv[6])>10)return 2;
 SherpaOnnxOfflineTtsConfig c{};c.model.vits.model=argv[1];c.model.vits.tokens=argv[2];c.model.vits.data_dir=argv[3];c.model.vits.noise_scale=.667f;c.model.vits.noise_scale_w=.8f;c.model.vits.length_scale=1;c.model.num_threads=atoi(argv[5]);c.model.provider="cpu";c.max_num_sentences=1;c.silence_scale=1;
 auto start=Clock::now();auto*engine=SherpaOnnxCreateOfflineTts(&c);if(!engine)return 3;double load=secs(start);
 for(int i=0;i<atoi(argv[6]);i++){
  start=Clock::now();std::pair<Clock::time_point,double> callback{start,-1};auto*a=SherpaOnnxOfflineTtsGenerateWithCallbackWithArg(engine,text.c_str(),0,1,cb,&callback);double gen=secs(start);if(!a)return 4;
  printf("threads=%d run=%d chars=%zu load=%.6f generate=%.6f first=%.6f audio=%.6f samples=%d\n",atoi(argv[5]),i,text.size(),load,gen,callback.second,double(a->n)/a->sample_rate,a->n);fflush(stdout);
  if(argc>7){std::string out=std::string(argv[7])+"-"+std::to_string(i)+".wav";SherpaOnnxWriteWave(a->samples,a->n,a->sample_rate,out.c_str());}
  SherpaOnnxDestroyOfflineTtsGeneratedAudio(a);
 }
 start=Clock::now();SherpaOnnxDestroyOfflineTts(engine);printf("release=%.6f\n",secs(start));
}
