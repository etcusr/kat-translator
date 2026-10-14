#include "sherpa-onnx/c-api/c-api.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
using Clock=std::chrono::steady_clock;
static double seconds(Clock::time_point start) { return std::chrono::duration<double>(Clock::now()-start).count(); }
int main(int argc,char**argv) {
 if(argc<4) { fprintf(stderr,"Usage: asr-probe model-directory wav threads [repeats]\n");return 2; }
 std::string dir=argv[1],enc=dir+"/encoder.int8.onnx",dec=dir+"/decoder.onnx",join=dir+"/joiner.onnx",tokens=dir+"/tokens.txt";
 if(FILE*f=fopen((dir+"/decoder.int8.onnx").c_str(),"rb")) { fclose(f);dec=dir+"/decoder.int8.onnx";join=dir+"/joiner.int8.onnx"; }
 SherpaOnnxOfflineRecognizerConfig c{};
 c.feat_config.sample_rate=16000;c.feat_config.feature_dim=80;
 c.model_config.transducer.encoder=enc.c_str();c.model_config.transducer.decoder=dec.c_str();c.model_config.transducer.joiner=join.c_str();
 c.model_config.tokens=tokens.c_str();c.model_config.num_threads=atoi(argv[3]);c.model_config.provider="cpu";c.model_config.model_type="nemo_transducer";c.decoding_method="greedy_search";
 auto begin=Clock::now();auto*r=SherpaOnnxCreateOfflineRecognizer(&c);if(!r)return 3;
 printf("load_seconds=%.6f\n",seconds(begin));fflush(stdout);
 auto*w=SherpaOnnxReadWave(argv[2]);if(!w)return 4;
 printf("audio_seconds=%.6f\n",double(w->num_samples)/w->sample_rate);
 for(int i=0;i<(argc>4?atoi(argv[4]):3);++i) {
  auto*s=SherpaOnnxCreateOfflineStream(r);begin=Clock::now();
  SherpaOnnxAcceptWaveformOffline(s,w->sample_rate,w->samples,w->num_samples);
  SherpaOnnxDecodeOfflineStream(r,s);auto*result=SherpaOnnxGetOfflineStreamResult(s);
  printf("run=%d seconds=%.6f text=%s\n",i,seconds(begin),result?result->text:"ERROR");fflush(stdout);
  if(result)SherpaOnnxDestroyOfflineRecognizerResult(result);SherpaOnnxDestroyOfflineStream(s);
 }
 SherpaOnnxFreeWave(w);SherpaOnnxDestroyOfflineRecognizer(r);return 0;
}
