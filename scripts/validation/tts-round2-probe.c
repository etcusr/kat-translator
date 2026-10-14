#include "sherpa-onnx/c-api/c-api.h"
#include <stdio.h>
#include <math.h>
#include <time.h>
int main(int argc, char **argv) {
 if(argc!=6)return 64;
 SherpaOnnxOfflineTtsConfig c={0};
 c.model.vits.model=argv[1]; c.model.vits.tokens=argv[2];c.model.vits.data_dir=argv[3];
 c.model.vits.noise_scale=.667;c.model.vits.noise_scale_w=.8;c.model.vits.length_scale=1;
 c.model.num_threads=2;c.model.provider="cpu";c.max_num_sentences=1;c.silence_scale=1;
 struct timespec a,b; clock_gettime(CLOCK_MONOTONIC,&a);
 const SherpaOnnxOfflineTts *tts=SherpaOnnxCreateOfflineTts(&c);if(!tts)return 1;
 const SherpaOnnxGeneratedAudio *audio=SherpaOnnxOfflineTtsGenerate(tts,argv[4],0,1);
 clock_gettime(CLOCK_MONOTONIC,&b);
 if(!audio||audio->n<=0||audio->sample_rate<=0)return 2;
 double energy=0;for(int i=0;i<audio->n;i++){if(!isfinite(audio->samples[i]))return 3;energy+=audio->samples[i]*audio->samples[i];}
 if(energy<.001)return 4;
 if(!SherpaOnnxWriteWave(audio->samples,audio->n,audio->sample_rate,argv[5]))return 5;
 printf("{\"seconds\":%.3f,\"audioSeconds\":%.3f,\"energy\":%.5f,\"sampleRate\":%d}\n",(b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)/1e9,(double)audio->n/audio->sample_rate,energy,audio->sample_rate);
 SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);SherpaOnnxDestroyOfflineTts(tts);return 0;
}
